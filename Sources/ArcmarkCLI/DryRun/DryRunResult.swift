import Foundation

/// Structured dry-run output showing what a mutation would do without persisting.
struct DryRunResult: Codable, OutputFormattable {
    let action: String
    let description: String
    let valid: Bool
    let warnings: [String]

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func toText() -> String {
        var lines = ["[dry-run] \(action): \(description)"]
        if !warnings.isEmpty {
            for warning in warnings {
                lines.append("  warning: \(warning)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
