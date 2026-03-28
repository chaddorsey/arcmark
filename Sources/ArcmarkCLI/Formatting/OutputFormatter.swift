import Foundation

/// Protocol for command results that can be rendered in multiple formats.
protocol OutputFormattable {
    /// JSON-serializable representation.
    func toJSON() -> Any
    /// Human-readable table/text representation.
    func toText() -> String
}

/// Central output routing based on format selection.
enum OutputFormatter {
    /// Render a result and print to stdout.
    static func print(_ result: OutputFormattable, format: OutputFormat) {
        switch format {
        case .json:
            printJSON(result.toJSON())
        case .table:
            Swift.print(result.toText())
        }
    }

    /// Render a raw JSON value to stdout.
    static func printJSON(_ value: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            Swift.print(string)
        }
    }

    /// Print a simple success message respecting format and quiet flags.
    static func printSuccess(_ message: String, format: OutputFormat, quiet: Bool) {
        guard !quiet else { return }
        switch format {
        case .json:
            printJSON(["status": "ok", "message": message])
        case .table:
            Swift.print(message)
        }
    }

    /// Print a structured error.
    static func printError(_ error: CLIError, format: OutputFormat) {
        switch format {
        case .json:
            printJSON(error.toJSON())
        case .table:
            Swift.print("Error: \(error.localizedDescription)")
        }
    }
}
