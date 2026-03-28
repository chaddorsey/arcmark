import Foundation

/// Structured errors for CLI output. Renders as JSON when in JSON mode,
/// human-readable text otherwise.
enum CLIError: Error, LocalizedError {
    case notFound(entity: String, reference: String, suggestions: [String])
    case ambiguousReference(entity: String, reference: String, candidates: [String])
    case invalidInput(field: String, value: String, reason: String)
    case validationFailed(message: String)
    case dataError(message: String)

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
        switch self {
        case .notFound(let entity, let reference, let suggestions):
            return [
                "error": "not_found",
                "entity": entity,
                "reference": reference,
                "suggestions": suggestions,
                "hint": "Use 'arcmark \(entity) list --json' to see all \(entity)s."
            ]
        case .ambiguousReference(let entity, let reference, let candidates):
            return [
                "error": "ambiguous_reference",
                "entity": entity,
                "reference": reference,
                "candidates": candidates,
                "hint": "Use a UUID for an exact match."
            ]
        case .invalidInput(let field, let value, let reason):
            return [
                "error": "invalid_input",
                "field": field,
                "value": value,
                "reason": reason
            ]
        case .validationFailed(let message):
            return [
                "error": "validation_failed",
                "message": message
            ]
        case .dataError(let message):
            return [
                "error": "data_error",
                "message": message
            ]
        }
    }
}
