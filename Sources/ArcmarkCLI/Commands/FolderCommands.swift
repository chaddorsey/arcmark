import ArgumentParser
import ArcmarkData
import Foundation

struct FolderGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folder",
        abstract: "Manage folders.",
        subcommands: [
            List.self,
            Add.self,
            Rename.self,
            Delete.self,
            Move.self,
            Expand.self,
            Collapse.self,
        ]
    )

    // MARK: - folder list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List folder hierarchy in a workspace."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Workspace to list folders from (UUID or name). Defaults to all workspaces.")
        var workspace: String?

        @Option(name: .long, help: "Maximum depth to display (0 = top-level only).")
        var depth: Int?

        mutating func run() async throws {
            let model = try await globals.makeModel()
            let state = await model.state
            let format = globals.effectiveFormat

            let targetWorkspaces: [Workspace]
            if let wsRef = workspace {
                let ws = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
                targetWorkspaces = [ws]
            } else {
                targetWorkspaces = state.workspaces
            }

            var entries: [FolderEntry] = []
            for ws in targetWorkspaces {
                collectFolders(from: ws.items, workspaceId: ws.id, workspaceName: ws.name, parentId: nil, currentDepth: 0, maxDepth: depth, into: &entries)
            }

            let output = FolderListOutput(entries: entries)
            OutputFormatter.print(output, format: format)
        }

        private func collectFolders(from nodes: [Node], workspaceId: UUID, workspaceName: String, parentId: UUID?, currentDepth: Int, maxDepth: Int?, into entries: inout [FolderEntry]) {
            for node in nodes {
                if case .folder(let folder) = node {
                    let linkCount = folder.children.filter { if case .link = $0 { return true }; return false }.count
                    let folderCount = folder.children.filter { if case .folder = $0 { return true }; return false }.count

                    entries.append(FolderEntry(
                        id: folder.id.uuidString,
                        name: folder.name,
                        isExpanded: folder.isExpanded,
                        childLinkCount: linkCount,
                        childFolderCount: folderCount,
                        workspaceId: workspaceId.uuidString,
                        workspaceName: workspaceName,
                        parentId: parentId?.uuidString,
                        depth: currentDepth
                    ))

                    if maxDepth == nil || currentDepth < maxDepth! {
                        collectFolders(from: folder.children, workspaceId: workspaceId, workspaceName: workspaceName, parentId: folder.id, currentDepth: currentDepth + 1, maxDepth: maxDepth, into: &entries)
                    }
                }
            }
        }
    }

    // MARK: - folder add

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new folder."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Name for the new folder.")
        var name: String

        @Option(name: .long, help: "Workspace to add to (UUID or name).")
        var workspace: String?

        @Option(name: .long, help: "Parent folder path (e.g., 'APIs/Internal').")
        var parent: String?

        mutating func run() async throws {
            try InputValidator.validateNotEmpty(name, field: "name")
            try InputValidator.validateNoControlChars(name, field: "name")
            if let parent { try InputValidator.validateNoPathTraversal(parent, field: "parent") }
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)

            let parentId: UUID?
            if let parentPath = parent {
                let resolved = try ReferenceResolver.resolveFolder(path: parentPath, in: ws)
                parentId = resolved.id
            } else {
                parentId = nil
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "folder.add",
                    description: "Create folder '\(name)' in workspace '\(ws.name)'" + (parent != nil ? " under '\(parent!)'" : ""),
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            let id = await model.addFolder(name: name, parentId: parentId, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": id.uuidString, "name": name, "workspaceId": ws.id.uuidString], message: "Created folder '\(name)'"),
                format: format
            )
        }
    }

    // MARK: - folder rename

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a folder."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Folder to rename (UUID or name).")
        var ref: String

        @Argument(help: "New name.")
        var newName: String

        @Option(name: .long, help: "Workspace containing the folder (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            try InputValidator.validateNotEmpty(newName, field: "name")
            try InputValidator.validateNoControlChars(newName, field: "name")
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .folder = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a link, not a folder. Use 'link rename' instead.")
            }

            if globals.dryRun {
                let result = DryRunResult(
                    action: "folder.rename",
                    description: "Rename folder '\(nodeResult.node.displayName)' to '\(newName)'",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.renameNode(id: nodeResult.node.id, newName: newName, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "name": newName], message: "Renamed folder to '\(newName)'"),
                format: format
            )
        }
    }

    // MARK: - folder delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a folder and all its contents."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Folder to delete (UUID or name).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the folder (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .folder(let folder) = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a link, not a folder. Use 'link delete' instead.")
            }

            let childCount = countNodes(folder.children)

            if globals.dryRun {
                var warnings: [String] = []
                if childCount > 0 {
                    warnings.append("Folder contains \(childCount) item(s) that will be permanently deleted.")
                }
                let result = DryRunResult(
                    action: "folder.delete",
                    description: "Delete folder '\(folder.name)' (\(folder.id.uuidString))",
                    valid: true, warnings: warnings
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.deleteNode(id: folder.id, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": folder.id.uuidString, "name": folder.name], message: "Deleted folder '\(folder.name)' (\(childCount) items)"),
                format: format
            )
        }
    }

    // MARK: - folder move

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a folder to a different location."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Folder to move (UUID or name).")
        var ref: String

        @Option(name: .long, help: "Source workspace (UUID or name).")
        var from: String?

        @Option(name: .long, help: "Target workspace for cross-workspace move (UUID or name).")
        var workspace: String?

        @Option(name: .long, help: "Target parent folder path.")
        var parent: String?

        @Option(name: .long, help: "Position within the target (0-based index).")
        var at: Int?

        mutating func run() async throws {
            if let parent { try InputValidator.validateNoPathTraversal(parent, field: "parent") }
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let sourceWs = try resolveWorkspaceOrFirst(from, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: sourceWs)

            guard case .folder = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a link, not a folder. Use 'link move' instead.")
            }

            if globals.dryRun {
                let targetDesc = workspace != nil ? "workspace '\(workspace!)'" : (parent != nil ? "folder '\(parent!)'" : "root")
                let result = DryRunResult(
                    action: "folder.move",
                    description: "Move folder '\(nodeResult.node.displayName)' to \(targetDesc)",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            if let wsRef = workspace {
                let targetWs = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
                await model.moveNodeToWorkspace(id: nodeResult.node.id, toWorkspaceId: targetWs.id, fromWorkspace: sourceWs.id)
                if let parentPath = parent {
                    let targetFolder = try ReferenceResolver.resolveFolder(path: parentPath, in: targetWs)
                    await model.moveNode(id: nodeResult.node.id, toParentId: targetFolder.id, index: at ?? 0, inWorkspace: targetWs.id)
                }
            } else {
                let parentId: UUID?
                if let parentPath = parent {
                    let targetFolder = try ReferenceResolver.resolveFolder(path: parentPath, in: sourceWs)
                    parentId = targetFolder.id
                } else {
                    parentId = nil
                }
                await model.moveNode(id: nodeResult.node.id, toParentId: parentId, index: at ?? 0, inWorkspace: sourceWs.id)
            }

            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "name": nodeResult.node.displayName], message: "Moved folder '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }

    // MARK: - folder expand

    struct Expand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a folder to expanded state (affects GUI display)."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Folder to expand (UUID or name).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the folder (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .folder = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a link, not a folder.")
            }

            if globals.dryRun {
                let result = DryRunResult(action: "folder.expand", description: "Expand folder '\(nodeResult.node.displayName)'", valid: true, warnings: [])
                OutputFormatter.print(result, format: format)
                return
            }

            await model.setFolderExpanded(id: nodeResult.node.id, isExpanded: true, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "name": nodeResult.node.displayName, "isExpanded": "true"], message: "Expanded '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }

    // MARK: - folder collapse

    struct Collapse: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a folder to collapsed state (affects GUI display)."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Folder to collapse (UUID or name).")
        var ref: String

        @Option(name: .long, help: "Workspace containing the folder (UUID or name).")
        var workspace: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state

            let ws = try resolveWorkspaceOrFirst(workspace, in: state)
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)

            guard case .folder = nodeResult.node else {
                throw CLIError.validationFailed(message: "'\(ref)' is a link, not a folder.")
            }

            if globals.dryRun {
                let result = DryRunResult(action: "folder.collapse", description: "Collapse folder '\(nodeResult.node.displayName)'", valid: true, warnings: [])
                OutputFormatter.print(result, format: format)
                return
            }

            await model.setFolderExpanded(id: nodeResult.node.id, isExpanded: false, inWorkspace: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": nodeResult.node.id.uuidString, "name": nodeResult.node.displayName, "isExpanded": "false"], message: "Collapsed '\(nodeResult.node.displayName)'"),
                format: format
            )
        }
    }
}

// MARK: - Output Types

struct FolderEntry: Codable {
    let id: String
    let name: String
    let isExpanded: Bool
    let childLinkCount: Int
    let childFolderCount: Int
    let workspaceId: String
    let workspaceName: String
    let parentId: String?
    let depth: Int
}

struct FolderListOutput: OutputFormattable {
    let entries: [FolderEntry]

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    func toText() -> String {
        if entries.isEmpty { return "No folders found." }
        var lines: [String] = []
        for entry in entries {
            let indent = String(repeating: "  ", count: entry.depth + 1)
            let expanded = entry.isExpanded ? "v" : ">"
            let contents = "\(entry.childLinkCount) links, \(entry.childFolderCount) folders"
            lines.append("\(indent)\(expanded) \(entry.name)  (\(contents))")
        }
        return lines.joined(separator: "\n")
    }
}
