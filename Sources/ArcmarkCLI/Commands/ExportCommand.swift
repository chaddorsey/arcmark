import ArgumentParser
import ArcmarkData
import Foundation

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export workspaces to JSON or Markdown."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Workspace to export (UUID or name). Exports all if omitted.")
    var workspace: String?

    @Option(name: .customLong("export-format"), help: "Export format: json (default), md (Markdown).")
    var exportFormat: ExportFormat = .json

    @Option(name: .long, help: "Output file path. Writes to stdout if omitted.")
    var output: String?

    @Flag(name: .long, help: "Write a timestamped backup copy to the data directory's backups/ folder.")
    var snapshot = false

    mutating func run() async throws {
        let model = try await globals.makeModel()
        let state = await model.state

        let targetWorkspaces: [Workspace]
        if let wsRef = workspace {
            let ws = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
            targetWorkspaces = [ws]
        } else {
            targetWorkspaces = state.workspaces
        }

        let content: String
        switch exportFormat {
        case .json:
            content = try exportJSON(workspaces: targetWorkspaces, fullState: workspace == nil ? state : nil)
        case .md:
            content = exportMarkdown(workspaces: targetWorkspaces)
        }

        if let outputPath = output {
            try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
            if !globals.quiet {
                FileHandle.standardError.write(Data("Exported to \(outputPath)\n".utf8))
            }
        } else {
            Swift.print(content)
        }

        if snapshot {
            let store = globals.makeStore()
            let backupsDir = store.baseDirectory.appendingPathComponent("backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let filename = "data-\(formatter.string(from: Date())).json"
            let snapshotURL = backupsDir.appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: snapshotURL, options: [.atomic])

            if !globals.quiet {
                FileHandle.standardError.write(Data("Snapshot saved to \(snapshotURL.path)\n".utf8))
            }
        }
    }

    private func exportJSON(workspaces: [Workspace], fullState: AppState?) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        if let state = fullState {
            data = try encoder.encode(state)
        } else {
            data = try encoder.encode(workspaces)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func exportMarkdown(workspaces: [Workspace]) -> String {
        var lines: [String] = []
        for ws in workspaces {
            lines.append("# \(ws.name)")
            lines.append("")

            // Pinned links
            if !ws.pinnedLinks.isEmpty {
                lines.append("## Pinned")
                lines.append("")
                for link in ws.pinnedLinks {
                    lines.append("- [\(link.title)](\(link.url))")
                }
                lines.append("")
            }

            // Tree items
            renderMarkdownNodes(ws.items, depth: 2, into: &lines)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func renderMarkdownNodes(_ nodes: [Node], depth: Int, into lines: inout [String]) {
        let heading = String(repeating: "#", count: min(depth, 6))
        for node in nodes {
            switch node {
            case .link(let link):
                lines.append("- [\(link.title)](\(link.url))")
            case .folder(let folder):
                lines.append("")
                lines.append("\(heading) \(folder.name)")
                lines.append("")
                renderMarkdownNodes(folder.children, depth: depth + 1, into: &lines)
            }
        }
    }
}

enum ExportFormat: String, ExpressibleByArgument, CaseIterable {
    case json
    case md
}
