import ArgumentParser
import ArcmarkData
import Foundation

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import bookmarks from a file."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Path to the bookmark file.")
    var file: String

    @Option(name: .long, help: "Import format: arc, chrome, txt. Auto-detected from extension if omitted.")
    var format: ImportFormat?

    @Option(name: .long, help: "Target workspace for imported links (UUID or name). Creates new workspaces if format supports multiple (arc).")
    var workspace: String?

    mutating func run() async throws {
        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CLIError.invalidInput(field: "file", value: file, reason: "file not found")
        }

        let importFormat = format ?? detectFormat(from: fileURL)
        guard let importFormat else {
            throw CLIError.invalidInput(field: "format", value: fileURL.pathExtension, reason: "cannot detect format. Specify --format (arc, chrome, txt).")
        }

        let outputFormat = globals.effectiveFormat
        let model = try await globals.makeModel()

        switch importFormat {
        case .arc:
            try await importArc(fileURL: fileURL, model: model, format: outputFormat)
        case .chrome:
            try await importChrome(fileURL: fileURL, model: model, format: outputFormat)
        case .txt:
            try await importTxt(fileURL: fileURL, model: model, format: outputFormat)
        }
    }

    private func importArc(fileURL: URL, model: AppModel, format: OutputFormat) async throws {
        if workspace != nil {
            throw CLIError.validationFailed(message: "--workspace is not supported with arc format. Arc import creates workspaces from the Arc sidebar structure.")
        }
        let service = ArcImportService()
        let result = await service.importFromArc(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            if globals.dryRun {
                let result = DryRunResult(
                    action: "import.arc",
                    description: "Import \(importResult.linksImported) links and \(importResult.foldersImported) folders across \(importResult.workspacesCreated) workspace(s)",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            for importedWs in importResult.workspaces {
                let wsId = await model.createWorkspace(name: importedWs.name, colorId: importedWs.colorId, selectAfterCreation: false)
                await importNodes(importedWs.nodes, into: wsId, parentId: nil, model: model)
            }

            OutputFormatter.print(
                MutationOutput(
                    entity: ["workspaces": String(importResult.workspacesCreated), "links": String(importResult.linksImported), "folders": String(importResult.foldersImported)],
                    message: "Imported \(importResult.linksImported) links from Arc"
                ),
                format: format
            )

        case .failure(let error):
            throw CLIError.dataError(message: error.localizedDescription)
        }
    }

    private func importChrome(fileURL: URL, model: AppModel, format: OutputFormat) async throws {
        let service = ChromeImportService()
        let result = await service.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            if globals.dryRun {
                let result = DryRunResult(
                    action: "import.chrome",
                    description: "Import \(importResult.linksImported) links and \(importResult.foldersImported) folders into workspace '\(importResult.workspace.name)'",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            let state = await model.state
            let targetWsId: UUID
            if let wsRef = workspace {
                let ws = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
                targetWsId = ws.id
            } else {
                targetWsId = await model.createWorkspace(name: importResult.workspace.name, colorId: importResult.workspace.colorId, selectAfterCreation: false)
            }

            await importNodes(importResult.workspace.nodes, into: targetWsId, parentId: nil, model: model)

            OutputFormatter.print(
                MutationOutput(
                    entity: ["links": String(importResult.linksImported), "folders": String(importResult.foldersImported)],
                    message: "Imported \(importResult.linksImported) links from Chrome bookmarks"
                ),
                format: format
            )

        case .failure(let error):
            throw CLIError.dataError(message: error.localizedDescription)
        }
    }

    private func importTxt(fileURL: URL, model: AppModel, format: OutputFormat) async throws {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let allLines = contents.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && URL(string: $0) != nil }

        // Filter to http/https URLs only (reject javascript:, file:, data:, etc.)
        var skipped = 0
        var urls: [String] = []
        for line in allLines {
            if let url = URL(string: line), let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                urls.append(line)
            } else {
                skipped += 1
            }
        }

        if urls.isEmpty {
            throw CLIError.validationFailed(message: "No valid URLs found in file.")
        }

        if globals.dryRun {
            var warnings: [String] = []
            if skipped > 0 {
                warnings.append("\(skipped) non-http(s) URL(s) will be skipped.")
            }
            let result = DryRunResult(
                action: "import.txt",
                description: "Import \(urls.count) URL(s) from plain text file",
                valid: true, warnings: warnings
            )
            OutputFormatter.print(result, format: format)
            return
        }

        let state = await model.state
        let targetWsId: UUID
        if let wsRef = workspace {
            let ws = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
            targetWsId = ws.id
        } else {
            if let firstId = state.workspaces.first?.id {
                targetWsId = firstId
            } else {
                targetWsId = await model.createWorkspace(name: "Imported", colorId: .defaultColor(), selectAfterCreation: false)
            }
        }

        var imported = 0
        for urlString in urls {
            let title: String
            if let url = URL(string: urlString) {
                title = await TitleFetcher.fetchTitle(for: url) ?? url.host ?? urlString
            } else {
                title = urlString
            }
            await model.addLink(urlString: urlString, title: title, parentId: nil, inWorkspace: targetWsId)
            imported += 1
        }

        OutputFormatter.print(
            MutationOutput(entity: ["links": String(imported)], message: "Imported \(imported) links from text file"),
            format: format
        )
    }

    private func importNodes(_ nodes: [Node], into workspaceId: UUID, parentId: UUID?, model: AppModel) async {
        for node in nodes {
            switch node {
            case .link(let link):
                await model.addLink(urlString: link.url, title: link.title, parentId: parentId, inWorkspace: workspaceId)
            case .folder(let folder):
                let folderId = await model.addFolder(name: folder.name, parentId: parentId, isExpanded: folder.isExpanded, inWorkspace: workspaceId)
                await importNodes(folder.children, into: workspaceId, parentId: folderId, model: model)
            }
        }
    }

    private func detectFormat(from url: URL) -> ImportFormat? {
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            return .chrome
        case "json":
            return .arc
        case "txt", "text", "csv":
            return .txt
        default:
            return nil
        }
    }
}

enum ImportFormat: String, ExpressibleByArgument, CaseIterable {
    case arc
    case chrome
    case txt
}
