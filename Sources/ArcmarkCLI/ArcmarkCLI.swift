import ArgumentParser
import ArcmarkData
import Foundation

@main
struct ArcmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arcmark",
        abstract: "Manage Arcmark bookmarks from the command line.",
        version: "0.1.9",
        subcommands: [
            WorkspaceGroup.self,
            // LinkGroup.self,
            // FolderGroup.self,
            // SearchCommand.self,
            // ImportCommand.self,
            // ExportCommand.self,
            // DedupeCommand.self,
            // GroupCommand.self,
            // BulkMoveCommand.self,
            // SchemaCommand.self,
        ]
    )
}

/// Global options inherited by all subcommands.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON regardless of terminal type.")
    var json = false

    @Option(name: .long, help: "Output format: json, table.")
    var format: OutputFormat?

    @Option(name: .long, help: "Override the data directory (default: ~/Library/Application Support/Arcmark/).")
    var dataDir: String?

    @Flag(name: .long, help: "Suppress informational messages.")
    var quiet = false

    @Flag(name: .long, help: "Validate and show what would change without persisting.")
    var dryRun = false

    /// Resolve the effective output format based on flags and TTY detection.
    var effectiveFormat: OutputFormat {
        if let explicit = format { return explicit }
        if json { return .json }
        return TTYDetection.isTerminal ? .table : .json
    }

    /// Create a DataStore using the configured data directory.
    func makeStore() -> DataStore {
        if let dir = dataDir {
            return DataStore(baseDirectory: URL(fileURLWithPath: dir, isDirectory: true))
        }
        return DataStore()
    }

    /// Create an AppModel for CLI use (no UserDefaults side effects).
    @MainActor
    func makeModel() -> AppModel {
        AppModel(store: makeStore(), defaults: nil)
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case json
    case table
}
