import Foundation

/// User-facing application errors. Bridges typed service-layer errors
/// (`GeminiClient.GeminiError`, pipeline errors, parser errors) into a
/// single enum so views can pattern-match without knowing about every
/// underlying error type.
enum AppError: LocalizedError, Equatable, Sendable {
    case apiKeyMissing
    case network(String)
    case rateLimited(retryAfter: TimeInterval)
    case serverBlocked(String)
    case parsing(String)
    case rendering
    case imageEmpty
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Gemini API key is not configured. Add your key in Settings."
        case .network(let message):
            return "Network error: \(message)"
        case .rateLimited(let retryAfter):
            return "Rate limited by Gemini API. Retry after \(Int(retryAfter)) seconds."
        case .serverBlocked(let message):
            return "Gemini server error: \(message)"
        case .parsing(let message):
            return "Failed to parse Gemini response: \(message)"
        case .rendering:
            return "Failed to render the drawing as a PNG image."
        case .imageEmpty:
            return "The annotation screenshot is empty."
        case .unknown(let message):
            return message
        }
    }

    /// Maps a service-layer error into the unified `AppError` representation.
    init(_ error: Error) {
        switch error {
        case let geminiError as GeminiClient.GeminiError:
            switch geminiError {
            case .invalidAPIKey:
                self = .apiKeyMissing
            case .rateLimited(let retryAfter):
                self = .rateLimited(retryAfter: retryAfter)
            case .serverError(let message):
                self = .serverBlocked(message)
            case .networkError(let inner):
                self = .network(inner.localizedDescription)
            case .parseError(let message):
                self = .parsing(message)
            }
        case AIConversionPipeline.PipelineError.imageRenderingFailed:
            self = .rendering
        case AIConversionPipeline.PipelineError.apiKeyMissing,
             RefinementPipeline.RefinementError.apiKeyMissing:
            self = .apiKeyMissing
        case RefinementPipeline.RefinementError.emptyAnnotationImage:
            self = .imageEmpty
        case let parseError as CodeGenerationResponse.ParseError:
            self = .parsing(parseError.errorDescription ?? "unknown parse failure")
        case let appError as AppError:
            self = appError
        default:
            self = .unknown(error.localizedDescription)
        }
    }
}
