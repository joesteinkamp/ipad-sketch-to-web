import XCTest
@testable import SketchToWeb

final class GeminiClientTests: XCTestCase {

    // MARK: - Error Equality

    func testGeminiErrorEquality() {
        XCTAssertEqual(
            GeminiClient.GeminiError.invalidAPIKey,
            GeminiClient.GeminiError.invalidAPIKey
        )
        XCTAssertEqual(
            GeminiClient.GeminiError.rateLimited(retryAfter: 5),
            GeminiClient.GeminiError.rateLimited(retryAfter: 5)
        )
        XCTAssertNotEqual(
            GeminiClient.GeminiError.rateLimited(retryAfter: 5),
            GeminiClient.GeminiError.rateLimited(retryAfter: 10)
        )
        XCTAssertEqual(
            GeminiClient.GeminiError.serverError("test"),
            GeminiClient.GeminiError.serverError("test")
        )
        XCTAssertNotEqual(
            GeminiClient.GeminiError.serverError("a"),
            GeminiClient.GeminiError.serverError("b")
        )
        XCTAssertEqual(
            GeminiClient.GeminiError.parseError("x"),
            GeminiClient.GeminiError.parseError("x")
        )
    }

    // MARK: - Error Descriptions

    func testGeminiErrorDescriptions() {
        XCTAssertNotNil(GeminiClient.GeminiError.invalidAPIKey.errorDescription)
        XCTAssertTrue(
            GeminiClient.GeminiError.invalidAPIKey.errorDescription!.contains("API key")
        )

        let rateLimited = GeminiClient.GeminiError.rateLimited(retryAfter: 30)
        XCTAssertTrue(rateLimited.errorDescription!.contains("30"))

        let serverError = GeminiClient.GeminiError.serverError("internal failure")
        XCTAssertTrue(serverError.errorDescription!.contains("internal failure"))

        let parseError = GeminiClient.GeminiError.parseError("bad json")
        XCTAssertTrue(parseError.errorDescription!.contains("bad json"))
    }

    // MARK: - Initialization

    func testClientInitWithDefaults() {
        let client = GeminiClient(apiKey: "test-key")
        XCTAssertEqual(client.apiKey, "test-key")
        XCTAssertEqual(client.model, "gemini-3.1-pro-preview")
    }

    func testClientInitWithCustomModel() {
        let client = GeminiClient(apiKey: "key", model: "gemini-2.5-flash")
        XCTAssertEqual(client.model, "gemini-2.5-flash")
    }

    // MARK: - Stream Construction

    func testStreamMessageReturnsStream() {
        let client = GeminiClient(apiKey: "fake-key")
        let stream = client.streamMessage(
            systemPrompt: "test",
            imageData: Data(),
            userText: "hello"
        )
        // Verify the stream was created (type check is implicit).
        XCTAssertNotNil(stream)
    }

    // MARK: - Error Types Don't Match Across Cases

    func testDifferentErrorCasesAreNotEqual() {
        XCTAssertNotEqual(
            GeminiClient.GeminiError.invalidAPIKey,
            GeminiClient.GeminiError.serverError("test")
        )
        XCTAssertNotEqual(
            GeminiClient.GeminiError.parseError("x"),
            GeminiClient.GeminiError.serverError("x")
        )
    }
}
