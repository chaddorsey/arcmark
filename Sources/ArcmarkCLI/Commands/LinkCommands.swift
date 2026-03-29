import ArgumentParser
import ArcmarkData
import Foundation

struct LinkGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Manage links (bookmarks).",
        subcommands: [
            List.self,
            Add.self,
            Rename.self,
            EditURL.self,
            Delete.self,
            Move.self,
            Icon.self,
            Pin.self,
            Unpin.self,
        ]
    )

    // MARK: - link list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List links in a workspace."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Workspace to list links from (UUID or name). Defaults to all workspaces.")
        var workspace: String?

        @Option(name: .long, help: "Limit output to specific fields (comma-separated: id, title, url, faviconPath, customIcon, pinned, workspaceId, workspaceName, parentId, depth).")
        var fields: String?

        @Option(name: .long, help: "Maximum number of links to return.")
        var limit: Int?

        @Option(name: .long, help: "Maximum folder depth to traverse (0 = root only).")
        var depth: Int?

        @Flag(name: .long, help: "Output only URLs, one per line.")
        var urlsOnly = false

        mutating func run() async throws {
            if let limit, limit < 1 {
                throw CLIError.invalidInput(field: "limit", value: String(limit), reason: "must be a positive integer")
            }

            let model = try await globals.makeModel()
            let state = await model.state
            let format = globals.effectiveFormat

            var entries: [LinkEntry] = []

            let targetWorkspaces: [Workspace]
            if let wsRef = workspace {
                let ws = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
                targetWorkspaces = [ws]
            } else {
                targetWorkspaces = state.workspaces
            }

            for ws in targetWorkspaces {
                // Pinned links
                for link in ws.pinnedLinks {
                    entries.append(LinkEntry(
                        id: link.id.uuidString,
                        title: link.title,
                        url: link.url,
                        faviconPath: link.faviconPath,
                        customIcon: link.customIcon.map(describeIcon),
                        pinned: true,
                        workspaceId: ws.id.uuidString,
                        workspaceName: ws.name,
                        parentId: nil,
                        depth: 0
                    ))
                }
                // Tree items
                collectLinks(from: ws.items, workspaceId: ws.id, workspaceName: ws.name, parentId: nil, currentDepth: 0, maxDepth: depth, into: &entries)
            }

            if let limit { entries = Array(entries.prefix(limit)) }

            if urlsOnly {
                for entry in entries {
                    Swift.print(entry.url)
                }
                return
            }

            let output = LinkListOutput(entries: entries, fields: fields)
            OutputFormatter.print(output, format: format)
        }

        private func collectLinks(from nodes: [Node], workspaceId: UUID, workspaceName: String, parentId: UUID?, currentDepth: Int, maxDepth: Int?, into entries: inout [LinkEntry]) {
            for node in nodes {
                switch node {
                case .link(let link):
                    entries.append(LinkEntry(
                        id: link.id.uuidString,
                        title: link.title,
                        url: link.url,
                        faviconPath: link.faviconPath,
                        customIcon: link.customIcon.map(describeIcon),
                        pinned: false,
                        workspaceId: workspaceId.uuidString,
                        workspaceName: workspaceName,
                        parentId: parentId?.uuidString,
                        depth: currentDepth
                    ))
                case .folder(let folder):
                    if maxDepth == nil || currentDepth < maxDepth! {
                        collectLinks(from: folder.children, workspaceId: workspaceId, workspaceName: workspaceName, parentId: folder.id, currentDepth: currentDepth + 1, maxDepth: maxDepth, into: &entries)
                    }
                }
            }
        }
    }

    // MARK: - link add

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a link to a workspace."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "URL to add.")
        var url: String

        @Option(name: .long, help: "Workspace to add to (UUID or name). Defaults to the first workspace.")
        var workspace: String?

        @Option(name: .long, help: "Folder path to add into (e.g., 'APIs/Internal').")
        var folder: String?

        @Option(name: .long, help: "Custom title. If omitted, fetches the page title automatically.")
        var title: String?

        mutating func run() async throws {
            try InputValidator.validateURLScheme(url)
            if let title { try InputValidator.validateNoControlChars(title, field: "title") }
            if let folder {
                try InputValidator.validateNoPathTraversal(folder, field: "folder")
            }
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)

            let parentId: UUID?
            if let folderPath = folder {
                let resolved = try ReferenceResolver.resolveFolder(path: folderPath, in: ws)
                parentId = resolved.id
            } else {
                parentId = nil
            }

            // Resolve title
            let linkTitle: String
            if let title {
                linkTitle = title
            } else {
                if let parsedURL = URL(string: url) {
                    linkTitle = await TitleFetcher.fetchTitle(for: parsedURL) ?? parsedURL.host ?? url
                } else {
                    linkTitle = url
                }
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "link.add",
                    description: "Add link '\(linkTitle)' (\(url)) to workspace '\(ws.name)'" + (folder != nil ? " in folder '\(folder!)'" : ""),
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            let id = await model.addLink(urlString: url, title: linkTitle, parentId: parentId, inWorkspace: ws.id)
            let entry = LinkEntry(
                id: id.uuidString, title: linkTitle, url: url, faviconPath: nil, customIcon: nil,
                pinned: false, workspaceId: ws.id.uuidString, workspaceName: ws.name,
                parentId: parentId?.uuidString, depth: 0
            )
            OutputFormatter.print(MutationOutput(entity: entry, message: "Added link '\(linkTitle)'"), format: format)
        }
    }

    // MARK: - link rename

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a link."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to rename (UUID or title).")
        var ref: String

        @Argument(help: "New title.")
        var newTitle: String

        @Option(name: .long, help: "Workspace containing the link (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            try InputValidator.validateNotEmpty(newTitle, field: "title")
            try InputValidator.validateNoControlChars(newTitle, field: "title")
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .link = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a folder, not a link. Use 'folder rename' instead.")
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "link.rename",
                    description: "Rename '\(nodeResult.node.displayName)' to '\(newTitle)'",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            if nodeResult.isPinned {
                await model.renamePinnedLink(id: nodeResult.node.id, newName: newTitle, inWorkspace: ws.id)
            } else {
                await model.renameNode(id: nodeResult.node.id, newName: newTitle, inWorkspace: ws.id)
            }
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "title": newTitle], message: "Renamed to '\(newTitle)'"),
                format: format
            )
        }
    }

    // MARK: - link edit-url

    struct EditURL: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "edit-url",
            abstract: "Change a link's URL."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to edit (UUID or title).")
        var ref: String

        @Argument(help: "New URL.")
        var newURL: String

        @Option(name: .long, help: "Workspace containing the link (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            try InputValidator.validateURLScheme(newURL)
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .link = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a folder, not a link. Use 'folder' commands instead.")
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "link.edit-url",
                    description: "Change URL of '\(nodeResult.node.displayName)' to '\(newURL)'",
                    valid: true, warnings: ["This will clear the favicon."]
                )
                OutputFormatter.print(result, format: format)
                return
            }

            if nodeResult.isPinned {
                await model.updatePinnedLinkUrl(id: nodeResult.node.id, newUrl: newURL, inWorkspace: ws.id)
            } else {
                await model.updateLinkUrl(id: nodeResult.node.id, newUrl: newURL, inWorkspace: ws.id)
            }
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "url": newURL], message: "Updated URL to '\(newURL)'"),
                format: format
            )
        }
    }

    // MARK: - link delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a link."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to delete (UUID or title).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the link (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .link = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a folder, not a link. Use 'folder delete' instead.")
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "link.delete",
                    description: "Delete link '\(nodeResult.node.displayName)'" + (nodeResult.isPinned ? " (pinned)" : ""),
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            if nodeResult.isPinned {
                await model.unpinLink(id: nodeResult.node.id, inWorkspace: ws.id)
            }
            await model.deleteNode(id: nodeResult.node.id, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "title": nodeResult.node.displayName], message: "Deleted '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }

    // MARK: - link move

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a link to a different location."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to move (UUID or title).")
        var ref: String

        @Option(name: .long, help: "Source workspace (UUID or name).")
        var from: String?

        @Option(name: .long, help: "Target workspace for cross-workspace move (UUID or name).")
        var workspace: String?

        @Option(name: .long, help: "Target folder path (e.g., 'APIs/Internal').")
        var folder: String?

        @Option(name: .long, help: "Position within the target (0-based index).")
        var at: Int?

        mutating func run() async throws {
            if let folder { try InputValidator.validateNoPathTraversal(folder, field: "folder") }
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let sourceWs = try resolveWorkspaceOrFirst(from, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: sourceWs)

            guard case .link = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a folder, not a link. Use 'folder move' instead.")
            }

            if globals.dryRun {
                let targetDesc = workspace != nil ? "workspace '\(workspace!)'" : (folder != nil ? "folder '\(folder!)'" : "root")
                let result = DryRunResult(
                    action: "link.move",
                    description: "Move '\(nodeResult.node.displayName)' to \(targetDesc)",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            // Cross-workspace move
            if let wsRef = workspace {
                let targetWs = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
                await model.moveNodeToWorkspace(id: nodeResult.node.id, toWorkspaceId: targetWs.id, fromWorkspace: sourceWs.id)
                // If a folder was specified, move within the target workspace
                if let folderPath = folder {
                    let targetFolder = try ReferenceResolver.resolveFolder(path: folderPath, in: targetWs)
                    await model.moveNode(id: nodeResult.node.id, toParentId: targetFolder.id, index: at ?? 0, inWorkspace: targetWs.id)
                }
            } else {
                // Same-workspace move
                let parentId: UUID?
                if let folderPath = folder {
                    let targetFolder = try ReferenceResolver.resolveFolder(path: folderPath, in: sourceWs)
                    parentId = targetFolder.id
                } else {
                    parentId = nil
                }
                await model.moveNode(id: nodeResult.node.id, toParentId: parentId, index: at ?? 0, inWorkspace: sourceWs.id)
            }

            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "title": nodeResult.node.displayName], message: "Moved '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }

    // MARK: - link icon

    struct Icon: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set or clear a link's custom icon."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to modify (UUID or title).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the link (UUID or name).")
        var workspace: String?

        @Option(name: .long, help: "Set an emoji icon (e.g., '🔥').")
        var emoji: String?

        @Option(name: .long, help: "Set an SF Symbol icon (e.g., 'star.fill').")
        var symbol: String?

        @Flag(name: .long, help: "Clear the custom icon.")
        var clear = false

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            let icon: CustomIcon?
            if clear {
                icon = nil
            } else if let emoji {
                icon = .emoji(emoji)
            } else if let symbol {
                icon = .sfSymbol(symbol)
            } else {
                throw CLIError.validationFailed(message: "Specify --emoji, --symbol, or --clear.")
            }

            if globals.dryRun {
                let desc = icon.map { describeIcon($0) } ?? "none"
                let result = DryRunResult(
                    action: "link.icon",
                    description: "Set icon of '\(nodeResult.node.displayName)' to \(desc)",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            if nodeResult.isPinned {
                await model.setPinnedLinkCustomIcon(id: nodeResult.node.id, icon: icon, inWorkspace: ws.id)
            } else {
                await model.setLinkCustomIcon(id: nodeResult.node.id, icon: icon, inWorkspace: ws.id)
            }

            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "icon": icon.map(describeIcon) ?? "none"], message: "Updated icon for '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }

    // MARK: - link pin

    struct Pin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Pin a link to the workspace's pinned section."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to pin (UUID or title).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the link (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            if nodeResult.isPinned {
                throw CLIError.validationFailed(message: "'\(nodeResult.node.displayName)' is already pinned.")
            }

            let canPin = await model.canPinMore(inWorkspace: ws.id)
            if !canPin {
                throw CLIError.validationFailed(message: "Workspace '\(ws.name)' has reached the maximum of \(Workspace.maxPinnedLinks) pinned links.")
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "link.pin",
                    description: "Pin '\(nodeResult.node.displayName)' in workspace '\(ws.name)'",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.pinLink(id: nodeResult.node.id, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "title": nodeResult.node.displayName], message: "Pinned '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }

    // MARK: - link unpin

    struct Unpin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Unpin a link from the workspace's pinned section."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Link to unpin (UUID or title).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the link (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            if !nodeResult.isPinned {
                throw CLIError.validationFailed(message: "'\(nodeResult.node.displayName)' is not pinned.")
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "link.unpin",
                    description: "Unpin '\(nodeResult.node.displayName)' from workspace '\(ws.name)'",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.unpinLink(id: nodeResult.node.id, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "title": nodeResult.node.displayName], message: "Unpinned '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }
}

// MARK: - Output Types

struct LinkEntry: Codable {
    let id: String
    let title: String
    let url: String
    let faviconPath: String?
    let customIcon: String?
    let pinned: Bool
    let workspaceId: String
    let workspaceName: String
    let parentId: String?
    let depth: Int
}

struct LinkListOutput: OutputFormattable {
    let entries: [LinkEntry]
    let fields: String?

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let fields {
            let requested = Set(fields.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            let fullData = try encoder.encode(entries)
            var dicts = try JSONSerialization.jsonObject(with: fullData) as? [[String: Any]] ?? []
            dicts = dicts.map { dict in dict.filter { requested.contains($0.key) } }
            return try JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys])
        }

        return try encoder.encode(entries)
    }

    func toText() -> String {
        if entries.isEmpty { return "No links found." }
        var lines: [String] = []
        for entry in entries {
            let indent = String(repeating: "  ", count: entry.depth + 1)
            let pinMark = entry.pinned ? " [pinned]" : ""
            lines.append("\(indent)\(entry.title)  (\(entry.url))\(pinMark)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helpers

func describeIcon(_ icon: CustomIcon) -> String {
    switch icon {
    case .emoji(let value): return "emoji:\(value)"
    case .sfSymbol(let value): return "sfSymbol:\(value)"
    case .cachedFavicon(let value): return "favicon:\(value)"
    }
}

func resolveWorkspaceOrFirst(_ ref: String?, in state: AppState) throws -> Workspace {
    if let ref {
        return try ReferenceResolver.resolveWorkspace(ref, in: state)
    }
    guard let first = state.workspaces.first else {
        throw CLIError.dataError(message: "No workspaces exist.")
    }
    return first
}
