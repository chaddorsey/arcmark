import ArcmarkData
import Foundation

/// Resolves string references (UUID, name, case-insensitive match) to entities.
enum ReferenceResolver {

    // MARK: - Workspace Resolution

    /// Resolve a workspace reference by UUID or name.
    static func resolveWorkspace(_ ref: String, in state: AppState) throws -> Workspace {
        // Try UUID first
        if let uuid = UUID(uuidString: ref),
           let ws = state.workspaces.first(where: { $0.id == uuid }) {
            return ws
        }

        // Try exact case-insensitive name match
        let matches = state.workspaces.filter {
            $0.name.lowercased() == ref.lowercased()
        }

        if matches.count == 1 {
            return matches[0]
        }

        if matches.count > 1 {
            throw CLIError.ambiguousReference(
                entity: "workspace",
                reference: ref,
                candidates: matches.map { "\($0.name) (\($0.id.uuidString.prefix(8))...)" }
            )
        }

        // No match — suggest similar names
        let suggestions = state.workspaces
            .map(\.name)
            .filter { $0.lowercased().contains(ref.lowercased()) }

        throw CLIError.notFound(
            entity: "workspace",
            reference: ref,
            suggestions: suggestions
        )
    }

    // MARK: - Node Resolution

    /// Result of resolving a node reference, including whether it's a pinned link.
    struct NodeResult {
        let node: Node
        let isPinned: Bool
    }

    /// Resolve a node reference within a workspace by UUID or name.
    /// Searches both workspace.items and workspace.pinnedLinks.
    static func resolveNode(_ ref: String, in workspace: Workspace) throws -> NodeResult {
        // Try UUID first
        if let uuid = UUID(uuidString: ref) {
            // Search items tree
            if let node = findNode(id: uuid, in: workspace.items) {
                return NodeResult(node: node, isPinned: false)
            }
            // Search pinned links
            if let link = workspace.pinnedLinks.first(where: { $0.id == uuid }) {
                return NodeResult(node: .link(link), isPinned: true)
            }
        }

        // Try case-insensitive name match across items + pinned links
        var matches: [(Node, Bool)] = [] // (node, isPinned)

        for node in flattenNodes(workspace.items) {
            if node.displayName.lowercased() == ref.lowercased() {
                matches.append((node, false))
            }
        }
        for link in workspace.pinnedLinks {
            if link.title.lowercased() == ref.lowercased() {
                matches.append((.link(link), true))
            }
        }

        if matches.count == 1 {
            return NodeResult(node: matches[0].0, isPinned: matches[0].1)
        }

        if matches.count > 1 {
            throw CLIError.ambiguousReference(
                entity: "node",
                reference: ref,
                candidates: matches.map { "\($0.0.displayName) (\($0.0.id.uuidString.prefix(8))...)" }
            )
        }

        // No match — suggest similar names
        let allNames = flattenNodes(workspace.items).map(\.displayName) + workspace.pinnedLinks.map(\.title)
        let suggestions = allNames.filter { $0.lowercased().contains(ref.lowercased()) }

        throw CLIError.notFound(
            entity: "node",
            reference: ref,
            suggestions: suggestions
        )
    }

    // MARK: - Folder Path Resolution

    /// Resolve a slash-separated folder path within a workspace (e.g., "Work/APIs/Internal").
    static func resolveFolder(path: String, in workspace: Workspace) throws -> Folder {
        let segments = path.split(separator: "/").map { String($0) }
        guard !segments.isEmpty else {
            throw CLIError.invalidInput(field: "folder", value: path, reason: "folder path cannot be empty")
        }

        var currentNodes = workspace.items
        var resolvedFolder: Folder?

        for segment in segments {
            let match = currentNodes.compactMap { node -> Folder? in
                if case .folder(let folder) = node, folder.name.lowercased() == segment.lowercased() {
                    return folder
                }
                return nil
            }

            guard let folder = match.first else {
                throw CLIError.notFound(entity: "folder", reference: segment, suggestions: currentNodes.compactMap {
                    if case .folder(let f) = $0 { return f.name }
                    return nil
                })
            }

            if match.count > 1 {
                throw CLIError.ambiguousReference(entity: "folder", reference: segment, candidates: match.map(\.name))
            }

            resolvedFolder = folder
            currentNodes = folder.children
        }

        guard let result = resolvedFolder else {
            throw CLIError.invalidInput(field: "folder", value: path, reason: "could not resolve path")
        }

        return result
    }

    // MARK: - Helpers

    private static func findNode(id: UUID, in nodes: [Node]) -> Node? {
        for node in nodes {
            if node.id == id { return node }
            if case .folder(let folder) = node,
               let found = findNode(id: id, in: folder.children) {
                return found
            }
        }
        return nil
    }

    private static func flattenNodes(_ nodes: [Node]) -> [Node] {
        var result: [Node] = []
        for node in nodes {
            result.append(node)
            if case .folder(let folder) = node {
                result.append(contentsOf: flattenNodes(folder.children))
            }
        }
        return result
    }
}
