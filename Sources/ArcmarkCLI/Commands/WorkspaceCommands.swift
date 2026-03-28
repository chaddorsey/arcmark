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

        @Option(name: .long, help: "Limit output to specific fields (comma-separated: id, name, colorId, colorName, itemCount, pinnedCount).")
        var fields: String?

        @Option(name: .long, help: "Maximum number of workspaces to return.")
        var limit: Int?

        mutating func run() async throws {
            if let limit, limit < 1 {
                throw CLIError.invalidInput(field: "limit", value: String(limit), reason: "must be a positive integer")
            }

            let model = try await globals.makeModel()
            let workspaces = await model.workspaces
            let format = globals.effectiveFormat

            let validFields: Set<String> = ["id", "name", "colorId", "colorName", "itemCount", "pinnedCount"]
            let ws = if let limit { Array(workspaces.prefix(limit)) } else { workspaces }

            var entries: [WorkspaceEntry] = []

            for workspace in ws {
                entries.append(WorkspaceEntry(
                    id: workspace.id.uuidString,
                    name: workspace.name,
                    colorId: workspace.colorId.rawValue,
                    colorName: workspace.colorId.name,
                    itemCount: countNodes(workspace.items),
                    pinnedCount: workspace.pinnedLinks.count
                ))
            }

            if let fields {
                let requested = Set(fields.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
                let unknown = requested.subtracting(validFields)
                if !unknown.isEmpty {
                    throw CLIError.invalidInput(
                        field: "fields",
                        value: unknown.sorted().joined(separator: ", "),
                        reason: "unknown field(s). Valid fields: \(validFields.sorted().joined(separator: ", "))"
                    )
                }
            }

            let output = WorkspaceListOutput(entries: entries, fields: fields)
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

struct WorkspaceEntry: Codable {
    let id: String
    let name: String
    let colorId: String
    let colorName: String
    let itemCount: Int
    let pinnedCount: Int
}

struct WorkspaceListOutput: OutputFormattable {
    let entries: [WorkspaceEntry]
    let fields: String?

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let fields {
            let requested = Set(fields.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            // Filter to requested fields by re-encoding through dictionaries
            let fullData = try encoder.encode(entries)
            var dicts = try JSONSerialization.jsonObject(with: fullData) as? [[String: Any]] ?? []
            dicts = dicts.map { dict in dict.filter { requested.contains($0.key) } }
            return try JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys])
        }

        return try encoder.encode(entries)
    }

    func toText() -> String {
        if entries.isEmpty { return "No workspaces." }
        var lines: [String] = []
        for entry in entries {
            let pinned = entry.pinnedCount > 0 ? ", \(entry.pinnedCount) pinned" : ""
            lines.append("  \(entry.name)  (\(entry.colorName), \(entry.itemCount) items\(pinned))")
        }
        return lines.joined(separator: "\n")
    }
}
