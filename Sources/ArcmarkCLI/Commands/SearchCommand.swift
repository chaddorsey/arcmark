import ArgumentParser
import ArcmarkData
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search links across all workspaces by title or URL."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Search query (matches link titles and URLs).")
    var query: String

    @Option(name: .long, help: "Limit search to a specific workspace (UUID or name).")
    var workspace: String?

    @Option(name: .long, help: "Maximum number of results.")
    var limit: Int?

    @Flag(name: .long, help: "Output only URLs, one per line.")
    var urlsOnly = false

    mutating func run() async throws {
        try InputValidator.validateNotEmpty(query, field: "query")
        if let limit, limit < 1 {
            throw CLIError.invalidInput(field: "limit", value: String(limit), reason: "must be a positive integer")
        }

        let model = try await globals.makeModel()
        let state = await model.state
        let format = globals.effectiveFormat
        let lower = query.lowercased()

        let targetWorkspaces: [Workspace]
        if let wsRef = workspace {
            let ws = try ReferenceResolver.resolveWorkspace(wsRef, in: state)
            targetWorkspaces = [ws]
        } else {
            targetWorkspaces = state.workspaces
        }

        var results: [SearchResult] = []

        for ws in targetWorkspaces {
            // Search pinned links
            for link in ws.pinnedLinks {
                if link.title.lowercased().contains(lower) || link.url.lowercased().contains(lower) {
                    results.append(SearchResult(
                        id: link.id.uuidString, title: link.title, url: link.url,
                        pinned: true, workspaceId: ws.id.uuidString, workspaceName: ws.name
                    ))
                }
            }
            // Search tree items
            searchNodes(ws.items, query: lower, workspaceId: ws.id, workspaceName: ws.name, into: &results)
        }

        if let limit { results = Array(results.prefix(limit)) }

        if urlsOnly {
            for result in results {
                Swift.print(result.url)
            }
            return
        }

        let output = SearchOutput(results: results, query: query)
        OutputFormatter.print(output, format: format)
    }

    private func searchNodes(_ nodes: [Node], query: String, workspaceId: UUID, workspaceName: String, into results: inout [SearchResult]) {
        for node in nodes {
            switch node {
            case .link(let link):
                if link.title.lowercased().contains(query) || link.url.lowercased().contains(query) {
                    results.append(SearchResult(
                        id: link.id.uuidString, title: link.title, url: link.url,
                        pinned: false, workspaceId: workspaceId.uuidString, workspaceName: workspaceName
                    ))
                }
            case .folder(let folder):
                searchNodes(folder.children, query: query, workspaceId: workspaceId, workspaceName: workspaceName, into: &results)
            }
        }
    }
}

// MARK: - Output Types

struct SearchResult: Codable {
    let id: String
    let title: String
    let url: String
    let pinned: Bool
    let workspaceId: String
    let workspaceName: String
}

struct SearchOutput: OutputFormattable {
    let results: [SearchResult]
    let query: String

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(results)
    }

    func toText() -> String {
        if results.isEmpty { return "No results for '\(query)'." }
        var lines = ["\(results.count) result(s) for '\(query)':"]
        for result in results {
            let pinned = result.pinned ? " [pinned]" : ""
            lines.append("  \(result.title)  (\(result.url))\(pinned)  [\(result.workspaceName)]")
        }
        return lines.joined(separator: "\n")
    }
}
