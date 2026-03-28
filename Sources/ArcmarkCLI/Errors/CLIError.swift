import Foundation

/// Structured errors for CLI output. Renders as JSON when in JSON mode,
/// human-readable text otherwise. All cases include a `message` field for
/// generic error handling by agents.
enum CLIError: Error, LocalizedError, CustomStringConvertible {
    case notFound(entity: String, reference: String, suggestions: [String])
    case ambiguousReference(entity: String, reference: String, candidates: [String])
    case invalidInput(field: String, value: String, reason: String)
    case validationFailed(message: String)
    case dataError(message: String)

    var description: String { errorDescription ?? "Unknown error" }

    var errorDescription: String? {
        switch self {
        case .notFound(let entity, let reference, let suggestions):
            var msg = "\(entity) '\(reference)' not found."
            if !suggestions.isEmpty {
                msg += " Did you mean: \(suggestions.joined(separator: ", "))?"
            }
            return msg
        case .ambiguousReference(let entity, let reference, let candidates):
            return "\(entity) '\(reference)' is ambiguous. Candidates: \(candidates.joined(separator: ", "))"
        case .invalidInput(let field, let value, let reason):
            return "Invalid \(field) '\(value)': \(reason)"
        case .validationFailed(let message):
            return message
        case .dataError(let message):
            return "Data error: \(message)"
        }
    }

    func toJSON() -> [String: Any] {
        var base: [String: Any] = ["message": errorDescription ?? "Unknown error"]

        switch self {
        case .notFound(let entity, let reference, let suggestions):
            base["error"] = "not_found"
            base["entity"] = entity
            base["reference"] = reference
            base["suggestions"] = suggestions
            base["hint"] = "Use 'arcmark \(entity) list --json' to see all \(entity)s."
        case .ambiguousReference(let entity, let reference, let candidates):
            base["error"] = "ambiguous_reference"
            base["entity"] = entity
            base["reference"] = reference
            base["candidates"] = candidates
            base["hint"] = "Use a UUID for an exact match."
        case .invalidInput(let field, let value, let reason):
            base["error"] = "invalid_input"
            base["field"] = field
            base["value"] = value
            base["reason"] = reason
        case .validationFailed:
            base["error"] = "validation_failed"
        case .dataError:
            base["error"] = "data_error"
        }

        return base
    }
}
