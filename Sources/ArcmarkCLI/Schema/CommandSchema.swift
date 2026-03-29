import Foundation

/// Describes a CLI command's interface for agent discovery via `arcmark schema`.
struct CommandSchema: Codable {
    let command: String
    let description: String
    let mutates: Bool
    let parameters: [ParameterSchema]
    let flags: [FlagSchema]

    struct ParameterSchema: Codable {
        let name: String
        let type: String
        let required: Bool
        let help: String
        let values: [String]?  // For enums
        let defaultValue: String?
    }

    struct FlagSchema: Codable {
        let name: String
        let help: String
    }
}

/// Protocol for commands that provide schema metadata for agent discovery.
protocol SchemaProviding {
    static var commandSchema: CommandSchema { get }
}
