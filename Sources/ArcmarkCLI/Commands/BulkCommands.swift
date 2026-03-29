import ArgumentParser
import ArcmarkData
import Foundation

struct GroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "group",
        abstract: "Group nodes into a new folder at their common parent."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(parsing: .captureForPassthrough, help: "Node references to group (UUIDs or titles).")
    var refs: [String]

    @Option(name: .long, help: "Name for the new folder.")
    var name: String

    @Option(name: .long, help: "Workspace containing the nodes (UUID or name).")
    var workspace: String?

    mutating func run() async throws {
        guard refs.count >= 2 else {
            throw CLIError.validationFailed(message: "At least 2 nodes are required for grouping.")
        }
        try InputValidator.validateNotEmpty(name, field: "name")
        try InputValidator.validateNoControlChars(name, field: "name")
        let format = globals.effectiveFormat
        let model = try await globals.makeModel()
        let state = await model.state

        let ws = try resolveWorkspaceOrFirst(workspace, in: state)

        var nodeIds: [UUID] = []
        for ref in refs {
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: ws)
            nodeIds.append(nodeResult.node.id)
        }

        if globals.dryRun {
            let result = DryRunResult(
                action: "group",
                description: "Group \(nodeIds.count) nodes into folder '\(name)' in workspace '\(ws.name)'",
                valid: true, warnings: []
            )
            OutputFormatter.print(result, format: format)
            return
        }

        let folderId = await model.groupNodesInNewFolder(nodeIds: nodeIds, folderName: name, inWorkspace: ws.id)
        let idStr = folderId?.uuidString ?? "unknown"
        OutputFormatter.print(
            MutationOutput(entity: ["id": idStr, "name": name, "childCount": String(nodeIds.count)], message: "Grouped \(nodeIds.count) nodes into '\(name)'"),
            format: format
        )
    }
}

struct BulkMoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move multiple nodes to a different workspace."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(parsing: .captureForPassthrough, help: "Node references to move (UUIDs or titles).")
    var refs: [String]

    @Option(name: .long, help: "Target workspace (UUID or name).")
    var workspace: String

    @Option(name: .long, help: "Source workspace (UUID or name).")
    var from: String?

    mutating func run() async throws {
        guard !refs.isEmpty else {
            throw CLIError.validationFailed(message: "At least 1 node reference is required.")
        }
        let format = globals.effectiveFormat
        let model = try await globals.makeModel()
        let state = await model.state

        let sourceWs = try resolveWorkspaceOrFirst(from, in: state)
        let targetWs = try ReferenceResolver.resolveWorkspace(workspace, in: state)

        var nodeIds: [UUID] = []
        for ref in refs {
            let nodeResult = try ReferenceResolver.resolveNode(ref, in: sourceWs)
            nodeIds.append(nodeResult.node.id)
        }

        if globals.dryRun {
            let result = DryRunResult(
                action: "move",
                description: "Move \(nodeIds.count) node(s) from '\(sourceWs.name)' to '\(targetWs.name)'",
                valid: true, warnings: []
            )
            OutputFormatter.print(result, format: format)
            return
        }

        await model.moveNodesToWorkspace(nodeIds: nodeIds, toWorkspaceId: targetWs.id, fromWorkspace: sourceWs.id)
        OutputFormatter.print(
            MutationOutput(entity: ["count": String(nodeIds.count), "toWorkspace": targetWs.name], message: "Moved \(nodeIds.count) node(s) to '\(targetWs.name)'"),
            format: format
        )
    }
}
