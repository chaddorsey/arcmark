import Foundation

/// Protocol for command results that can be rendered in multiple formats.
protocol OutputFormattable {
    /// Encode as JSON data.
    func encodeJSON() throws -> Data
    /// Human-readable table/text representation.
    func toText() -> String
}

/// Central output routing based on format selection.
enum OutputFormatter {
    /// Render a result and print to stdout.
    static func print(_ result: OutputFormattable, format: OutputFormat) {
        switch format {
        case .json:
            do {
                let data = try result.encodeJSON()
                if let string = String(data: data, encoding: .utf8) {
                    Swift.print(string)
                }
            } catch {
                FileHandle.standardError.write(Data("Error: failed to serialize JSON output: \(error.localizedDescription)\n".utf8))
                Foundation.exit(1)
            }
        case .table:
            Swift.print(result.toText())
        }
    }

    /// Print a structured CLIError respecting format.
    static func printError(_ error: CLIError, format: OutputFormat) {
        switch format {
        case .json:
            if let data = try? JSONSerialization.data(withJSONObject: error.toJSON(), options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data(string.utf8))
                FileHandle.standardError.write(Data("\n".utf8))
            }
        case .table:
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        }
    }
}
