import ArgumentParser
import ArcmarkData
import Foundation

struct WorkspaceGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workspace",
        abstract: "Manage workspaces.",
        subcommands: [
            List.self,
        ]
    )

    // MARK: - workspace list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all workspaces."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Limit output to specific fields (comma-separated: id, name, color, items, pinned).")
        var fields: String?

        @Option(name: .long, help: "Maximum number of workspaces to return.")
        var limit: Int?

        mutating func run() async throws {
            let model = await globals.makeModel()
            let workspaces = await model.workspaces
            let format = globals.effectiveFormat

            var results: [[String: Any]] = []
            let ws = if let limit { Array(workspaces.prefix(limit)) } else { workspaces }

            for workspace in ws {
                var entry: [String: Any] = [
                    "id": workspace.id.uuidString,
                    "name": workspace.name,
                    "colorId": workspace.colorId.rawValue,
                    "colorName": workspace.colorId.name,
                    "itemCount": countNodes(workspace.items),
                    "pinnedCount": workspace.pinnedLinks.count,
                ]

                if let fields {
                    let allowed = Set(fields.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
                    entry = entry.filter { allowed.contains($0.key) }
                }

                results.append(entry)
            }

            let output = WorkspaceListOutput(workspaces: workspaces, entries: results)
            OutputFormatter.print(output, format: format)
        }

        private func countNodes(_ nodes: [Node]) -> Int {
            nodes.reduce(0) { count, node in
                switch node {
                case .link: return count + 1
                case .folder(let folder): return count + 1 + countNodes(folder.children)
                }
            }
        }
    }
}

// MARK: - Output Types

struct WorkspaceListOutput: OutputFormattable {
    let workspaces: [Workspace]
    let entries: [[String: Any]]

    func toJSON() -> Any { entries }

    func toText() -> String {
        if workspaces.isEmpty { return "No workspaces." }
        var lines: [String] = []
        for (i, ws) in workspaces.enumerated() {
            let itemCount = entries.count > i
                ? (entries[i]["itemCount"] as? Int ?? 0)
                : 0
            let pinnedCount = entries.count > i
                ? (entries[i]["pinnedCount"] as? Int ?? 0)
                : 0
            let pinned = pinnedCount > 0 ? ", \(pinnedCount) pinned" : ""
            lines.append("  \(ws.name)  (\(ws.colorId.name), \(itemCount) items\(pinned))")
        }
        return lines.joined(separator: "\n")
    }
}
