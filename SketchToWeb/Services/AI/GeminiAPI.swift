import Foundation

/// Abstract interface to the Gemini generateContent API.
///
/// `GeminiClient` is the production implementation. Tests can substitute a
/// mock that records calls and returns scripted responses.
///
/// Streaming (`streamMessage`) is intentionally not part of this protocol.
/// `AsyncThrowingStream` mocking is awkward and only one call site uses it;
/// when streaming needs to be tested it can be added as a separate protocol.
protocol GeminiAPI: Sendable {
    func sendMessage(systemPrompt: String, imageData: Data, userText: String) async throws -> String
    func sendTextMessage(systemPrompt: String, userText: String) async throws -> String
}

extension GeminiClient: GeminiAPI {}
