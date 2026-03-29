import ArgumentParser
import Foundation

struct SchemaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Inspect command schemas for agent discovery."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Command to inspect (e.g., 'workspace.create', 'workspace', or omit for all).")
    var command: String?

    @Flag(name: .long, help: "Return the complete schema catalog for all commands.")
    var all = false

    mutating func run() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if all || command == nil {
            // Return all schemas
            let schemas = SchemaRegistry.allCommandSchemas
            let data = try encoder.encode(schemas)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            }
            return
        }

        guard let query = command else { return }

        // Try exact command match (e.g., "workspace.create")
        if let schema = SchemaRegistry.allSchemas[query] {
            let data = try encoder.encode(schema)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            }
            return
        }

        // Try resource group match (e.g., "workspace" -> all workspace.* commands)
        let resourceSchemas = SchemaRegistry.schemasForResource(query)
        if !resourceSchemas.isEmpty {
            let summary = resourceSchemas.map { schema in
                ["command": schema.command, "description": schema.description, "mutates": schema.mutates ? "true" : "false"]
            }
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            }
            return
        }

        throw CLIError.notFound(
            entity: "command",
            reference: query,
            suggestions: SchemaRegistry.allSchemas.keys.sorted().filter { $0.contains(query.lowercased()) }
        )
    }
}
