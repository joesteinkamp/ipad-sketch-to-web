import Foundation

/// A URLSession-based client for the Google Gemini API (generateContent endpoint).
/// Handles authentication, request construction, response parsing, and retry logic.
final class GeminiClient: Sendable {

    // MARK: - Properties

    let apiKey: String
    let model: String

    private let session: URLSession

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
    }

    private var streamingEndpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
    }

    private static let maxRetries = 2

    // MARK: - Errors

    enum GeminiError: LocalizedError, Equatable {
        case invalidAPIKey
        case rateLimited(retryAfter: TimeInterval)
        case serverError(String)
        case networkError(Error)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidAPIKey:
                return "Invalid Gemini API key. Please check your settings."
            case .rateLimited(let retryAfter):
                return "Rate limited by Gemini API. Retry after \(Int(retryAfter)) seconds."
            case .serverError(let message):
                return "Gemini server error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parseError(let message):
                return "Failed to parse Gemini response: \(message)"
            }
        }

        static func == (lhs: GeminiError, rhs: GeminiError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidAPIKey, .invalidAPIKey):
                return true
            case (.rateLimited(let a), .rateLimited(let b)):
                return a == b
            case (.serverError(let a), .serverError(let b)):
                return a == b
            case (.parseError(let a), .parseError(let b)):
                return a == b
            case (.networkError, .networkError):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Initialization

    /// Creates a new Gemini API client.
    ///
    /// - Parameters:
    ///   - apiKey: Your Google AI / Gemini API key.
    ///   - model: The model identifier to use. Defaults to `gemini-3.1-pro-preview`.
    init(apiKey: String, model: String = "gemini-3.1-pro-preview") {
        self.apiKey = apiKey
        self.model = model

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public API

    /// Sends a message containing a system prompt, an image, and user text to the Gemini API.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system-level instruction for the model.
    ///   - imageData: PNG image data to include in the user message.
    ///   - userText: The text portion of the user message.
    /// - Returns: The text content from the model's response.
    /// - Throws: `GeminiError` on failure.
    func sendMessage(systemPrompt: String, imageData: Data, userText: String) async throws -> String {
        let request = try buildRequest(systemPrompt: systemPrompt, imageData: imageData, userText: userText)
        return try await executeWithRetry(request: request)
    }

    /// Sends a text-only message (no image) to the Gemini API.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system-level instruction for the model.
    ///   - userText: The text portion of the user message.
    /// - Returns: The text content from the model's response.
    /// - Throws: `GeminiError` on failure.
    func sendTextMessage(systemPrompt: String, userText: String) async throws -> String {
        let request = try buildTextRequest(systemPrompt: systemPrompt, userText: userText)
        return try await executeWithRetry(request: request)
    }

    /// Streams a message to the Gemini API, yielding accumulated text as each chunk arrives.
    ///
    /// Uses the `streamGenerateContent` endpoint with server-sent events (`alt=sse`).
    /// Each yielded value is the full accumulated text so far (not just the new delta).
    func streamMessage(systemPrompt: String, imageData: Data, userText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try self.buildRequest(systemPrompt: systemPrompt, imageData: imageData, userText: userText)
                    request.url = self.streamingEndpoint

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await self.session.bytes(for: request)
                    } catch {
                        continuation.finish(throwing: GeminiError.networkError(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: GeminiError.networkError(
                            URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
                        ))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let error: GeminiError = switch httpResponse.statusCode {
                        case 401, 403:
                            .invalidAPIKey
                        case 429:
                            .rateLimited(retryAfter: self.parseRetryAfter(from: httpResponse))
                        default:
                            .serverError("HTTP \(httpResponse.statusCode)")
                        }
                        continuation.finish(throwing: error)
                        return
                    }

                    var accumulated = ""

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }

                        // SSE format: lines starting with "data: " contain the JSON payload.
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard let jsonData = jsonString.data(using: .utf8) else { continue }

                        // Parse the chunk — same candidates[0].content.parts[0].text structure.
                        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let candidates = json["candidates"] as? [[String: Any]],
                           let content = candidates.first?["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let text = parts.first?["text"] as? String {
                            accumulated += text
                            continuation.yield(accumulated)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Cancel the inner Task when the stream consumer stops listening.
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Construction

    private func buildTextRequest(systemPrompt: String, userText: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": userText]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 8192,
                "temperature": 0.2
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildRequest(systemPrompt: String, imageData: Data, userText: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Image = imageData.base64EncodedString()

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        [
                            "inlineData": [
                                "mimeType": "image/png",
                                "data": base64Image
                            ]
                        ],
                        [
                            "text": userText
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 8192,
                "temperature": 0.2
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Execution with Retry

    private func executeWithRetry(request: URLRequest) async throws -> String {
        var lastError: GeminiError?

        for attempt in 0...Self.maxRetries {
            do {
                return try await execute(request: request)
            } catch let error as GeminiError {
                switch error {
                case .rateLimited(let retryAfter):
                    lastError = error
                    if attempt < Self.maxRetries {
                        let delay = retryAfter > 0
                            ? retryAfter
                            : pow(2.0, Double(attempt + 1))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                default:
                    throw error
                }
            }
        }

        throw lastError ?? GeminiError.serverError("Unknown error after retries.")
    }

    private func execute(request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GeminiError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.networkError(
                URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
            )
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponseText(from: data)
        case 401, 403:
            throw GeminiError.invalidAPIKey
        case 429:
            let retryAfter = parseRetryAfter(from: httpResponse)
            throw GeminiError.rateLimited(retryAfter: retryAfter)
        case 400...499:
            let message = extractErrorMessage(from: data) ?? "Client error \(httpResponse.statusCode)."
            throw GeminiError.serverError(message)
        case 500...599:
            let message = extractErrorMessage(from: data) ?? "Server error \(httpResponse.statusCode)."
            throw GeminiError.serverError(message)
        default:
            throw GeminiError.serverError("Unexpected HTTP status code: \(httpResponse.statusCode).")
        }
    }

    // MARK: - Response Parsing

    /// Parses the Gemini generateContent response format:
    /// { "candidates": [{ "content": { "parts": [{ "text": "..." }] } }] }
    private func parseResponseText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.parseError("Response is not valid JSON.")
        }

        guard let candidates = json["candidates"] as? [[String: Any]] else {
            // Check for prompt feedback / blocked responses
            if let promptFeedback = json["promptFeedback"] as? [String: Any],
               let blockReason = promptFeedback["blockReason"] as? String {
                throw GeminiError.serverError("Request blocked: \(blockReason)")
            }
            throw GeminiError.parseError("Response missing 'candidates' array.")
        }

        guard let firstCandidate = candidates.first else {
            throw GeminiError.parseError("Response 'candidates' array is empty.")
        }

        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.parseError("Candidate missing 'content.parts'.")
        }

        guard let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError("First part does not contain 'text'.")
        }

        return text
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval {
        if let retryString = response.value(forHTTPHeaderField: "retry-after"),
           let seconds = TimeInterval(retryString) {
            return seconds
        }
        return 1.0
    }
}
