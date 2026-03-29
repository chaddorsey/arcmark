import ArgumentParser
import ArcmarkData
import Foundation

struct DedupeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dedupe",
        abstract: "Find duplicate URLs across workspaces."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Limit to a specific workspace (UUID or name).")
    var workspace: String?

    @Flag(name: .long, help: "Delete duplicates, keeping the first occurrence.")
    var delete = false

    @Option(name: .long, help: "Maximum number of duplicate groups to show.")
    var limit: Int?

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

        // Collect all links with normalized URLs
        var urlGroups: [String: [DupeEntry]] = [:]

        for ws in targetWorkspaces {
            collectLinksForDedupe(from: ws.items, workspaceId: ws.id, workspaceName: ws.name, pinned: false, into: &urlGroups)
            for link in ws.pinnedLinks {
                let normalized = normalizeURL(link.url)
                let entry = DupeEntry(id: link.id.uuidString, title: link.title, url: link.url, normalizedURL: normalized, workspaceId: ws.id.uuidString, workspaceName: ws.name, pinned: true)
                urlGroups[normalized, default: []].append(entry)
            }
        }

        // Filter to only duplicate groups
        var dupeGroups = urlGroups.filter { $0.value.count > 1 }
            .sorted { $0.value.count > $1.value.count }

        if let limit { dupeGroups = Array(dupeGroups.prefix(limit)) }

        let totalDupes = dupeGroups.reduce(0) { $0 + $1.value.count - 1 } // -1 because we keep the first

        if globals.dryRun || !delete {
            let output = DedupeOutput(groups: dupeGroups.map { DedupeGroup(normalizedURL: $0.key, entries: $0.value) }, totalDuplicates: totalDupes)
            OutputFormatter.print(output, format: format)
            return
        }

        // Delete duplicates (keep first occurrence)
        var deleted = 0
        for (_, entries) in dupeGroups {
            for entry in entries.dropFirst() {
                guard let wsId = UUID(uuidString: entry.workspaceId),
                      let nodeId = UUID(uuidString: entry.id) else { continue }
                if entry.pinned {
                    await model.unpinLink(id: nodeId, inWorkspace: wsId)
                }
                await model.deleteNode(id: nodeId, inWorkspace: wsId)
                deleted += 1
            }
        }

        OutputFormatter.print(
            MutationOutput(entity: ["deleted": String(deleted), "groups": String(dupeGroups.count)], message: "Deleted \(deleted) duplicate link(s) across \(dupeGroups.count) group(s)"),
            format: format
        )
    }

    private func collectLinksForDedupe(from nodes: [Node], workspaceId: UUID, workspaceName: String, pinned: Bool, into groups: inout [String: [DupeEntry]]) {
        for node in nodes {
            switch node {
            case .link(let link):
                let normalized = normalizeURL(link.url)
                let entry = DupeEntry(id: link.id.uuidString, title: link.title, url: link.url, normalizedURL: normalized, workspaceId: workspaceId.uuidString, workspaceName: workspaceName, pinned: pinned)
                groups[normalized, default: []].append(entry)
            case .folder(let folder):
                collectLinksForDedupe(from: folder.children, workspaceId: workspaceId, workspaceName: workspaceName, pinned: pinned, into: &groups)
            }
        }
    }

    /// Normalize a URL for deduplication: lowercase scheme+host, strip trailing slash,
    /// strip utm_* query parameters, normalize http/https to scheme-agnostic.
    private func normalizeURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString.lowercased()
        }

        // Normalize scheme (treat http and https as equivalent)
        components.scheme = nil

        // Lowercase host
        components.host = components.host?.lowercased()

        // Strip trailing slash from path
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }

        // Strip utm_* query parameters
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { !$0.name.hasPrefix("utm_") }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        return components.string ?? urlString.lowercased()
    }
}

// MARK: - Output Types

struct DupeEntry: Codable {
    let id: String
    let title: String
    let url: String
    let normalizedURL: String
    let workspaceId: String
    let workspaceName: String
    let pinned: Bool
}

struct DedupeGroup: Codable {
    let normalizedURL: String
    let entries: [DupeEntry]
}

struct DedupeOutput: OutputFormattable {
    let groups: [DedupeGroup]
    let totalDuplicates: Int

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let wrapper = DedupeJSONOutput(groups: groups, totalDuplicates: totalDuplicates)
        return try encoder.encode(wrapper)
    }

    func toText() -> String {
        if groups.isEmpty { return "No duplicates found." }
        var lines = ["\(totalDuplicates) duplicate(s) across \(groups.count) group(s):"]
        for group in groups {
            lines.append("")
            lines.append("  \(group.normalizedURL) (\(group.entries.count) occurrences):")
            for (i, entry) in group.entries.enumerated() {
                let keep = i == 0 ? " [keep]" : " [duplicate]"
                lines.append("    \(entry.title)  [\(entry.workspaceName)]\(keep)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct DedupeJSONOutput: Codable {
    let groups: [DedupeGroup]
    let totalDuplicates: Int
}
