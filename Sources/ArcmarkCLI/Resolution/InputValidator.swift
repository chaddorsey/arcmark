import ArcmarkData
import Foundation

/// Input validation for agent-hardened CLI. Rejects hallucinated or malicious inputs
/// with structured errors that enable self-correction.
enum InputValidator {

    /// Reject strings containing control characters (< ASCII 0x20), excluding common whitespace.
    static func validateNoControlChars(_ value: String, field: String) throws {
        for scalar in value.unicodeScalars {
            if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                throw CLIError.invalidInput(
                    field: field,
                    value: value,
                    reason: "contains control character (U+\(String(format: "%04X", scalar.value)))"
                )
            }
        }
    }

    /// Reject path traversal patterns in folder path references.
    static func validateNoPathTraversal(_ value: String, field: String) throws {
        let segments = value.split(separator: "/")
        for segment in segments {
            if segment == ".." || segment == "~" {
                throw CLIError.invalidInput(
                    field: field,
                    value: value,
                    reason: "path traversal not allowed"
                )
            }
        }
    }

    /// Validate a string is one of the allowed enum values. Returns the matched value.
    @discardableResult
    static func validateEnum(_ value: String, field: String, validValues: [String]) throws -> String {
        if let match = validValues.first(where: { $0.lowercased() == value.lowercased() }) {
            return match
        }
        throw CLIError.invalidInput(
            field: field,
            value: value,
            reason: "must be one of: \(validValues.joined(separator: ", "))"
        )
    }

    /// Validate a workspace color ID. Returns the matched WorkspaceColorId.
    static func validateColor(_ value: String) throws -> WorkspaceColorId {
        let validColors = WorkspaceColorId.allCases
        if let match = validColors.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
            return match
        }
        let suggestions = validColors.map { "\($0.rawValue) (\($0.name))" }
        throw CLIError.invalidInput(
            field: "color",
            value: value,
            reason: "must be one of: \(suggestions.joined(separator: ", "))"
        )
    }

    /// Validate a URL scheme is safe (http/https only).
    static func validateURLScheme(_ urlString: String) throws {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            throw CLIError.invalidInput(field: "url", value: urlString, reason: "invalid URL")
        }
        guard scheme == "http" || scheme == "https" else {
            throw CLIError.invalidInput(
                field: "url",
                value: urlString,
                reason: "only http and https URLs are allowed (got \(scheme))"
            )
        }
    }
}
