import ArgumentParser
import ArcmarkData
import Foundation

/// CLI version — read from VERSION file at runtime.
/// TODO: Generate this from VERSION file via build plugin to avoid runtime lookup.
let cliVersion: String = {
    let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let candidates = [
        execURL.deletingLastPathComponent().appendingPathComponent("../../../../VERSION"),
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("VERSION"),
    ]
    for url in candidates {
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
    }
    return "0.1.9" // Fallback if VERSION file not found
}()

@main
struct ArcmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arcmark",
        abstract: "Manage Arcmark bookmarks from the command line.",
        version: cliVersion,
        subcommands: [
            WorkspaceGroup.self,
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

    /// Create an AppModel for CLI use — throws on corrupt data instead of silently
    /// falling back to defaults. Suppresses UserDefaults side effects.
    @MainActor
    func makeModel() throws -> AppModel {
        try AppModel(store: makeStore(), defaults: nil, throwing: true)
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case json
    case table
}
