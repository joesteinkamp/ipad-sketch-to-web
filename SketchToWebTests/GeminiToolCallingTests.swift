import XCTest
@testable import SketchToWeb

/// Tests `GeminiClient.sendToolMessage` (function-calling extension) using a
/// globally-registered `URLProtocolStub`. The extension uses
/// `URLSession.shared` directly, so we register the stub on the global protocol
/// list for the duration of each test.
final class GeminiToolCallingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
        URLProtocol.registerClass(URLProtocolStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(URLProtocolStub.self)
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func client() -> GeminiClient {
        GeminiClient(apiKey: "test-key", model: "gemini-3.1-pro-preview")
    }

    private func endpoint() -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-preview:generateContent?key=test-key")!
    }

    // MARK: - Text response

    func testReturnsTextResponseWhenModelEmitsText() async throws {
        let body = """
        {"candidates":[{"content":{"parts":[{"text":"Hello there"}]}}]}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        let response = try await client().sendToolMessage(
            systemPrompt: "sys",
            turns: [.userText("hi")],
            tools: []
        )
        guard case .text(let text) = response else {
            XCTFail("Expected .text, got \(response)"); return
        }
        XCTAssertEqual(text, "Hello there")
    }

    func testConcatenatesMultipleTextParts() async throws {
        let body = """
        {"candidates":[{"content":{"parts":[
          {"text":"Part A "},
          {"text":"Part B"}
        ]}}]}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        let response = try await client().sendToolMessage(
            systemPrompt: "s", turns: [.userText("hi")], tools: []
        )
        guard case .text(let text) = response else { XCTFail(); return }
        XCTAssertEqual(text, "Part A Part B")
    }

    // MARK: - Function call response

    func testReturnsFunctionCallWhenModelInvokesTool() async throws {
        let body = """
        {"candidates":[{"content":{"parts":[
          {"functionCall":{"name":"get_design_context","args":{"node_id":"123:456"}}}
        ]}}]}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        let response = try await client().sendToolMessage(
            systemPrompt: "s",
            turns: [.userText("design")],
            tools: [
                GeminiToolDeclaration(
                    name: "get_design_context",
                    description: "Read",
                    parametersJSONSchema: Data("{}".utf8)
                )
            ]
        )
        guard case .functionCall(let call) = response else {
            XCTFail("Expected .functionCall, got \(response)"); return
        }
        XCTAssertEqual(call.name, "get_design_context")
        let args = try JSONSerialization.jsonObject(with: call.argumentsJSON) as? [String: Any]
        XCTAssertEqual(args?["node_id"] as? String, "123:456")
    }

    /// When the response includes both a text part and a function call, the
    /// function call wins (per `parseToolResponse`'s priority).
    func testPrefersFunctionCallOverText() async throws {
        let body = """
        {"candidates":[{"content":{"parts":[
          {"text":"thinking..."},
          {"functionCall":{"name":"do_thing","args":{}}}
        ]}}]}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        let response = try await client().sendToolMessage(
            systemPrompt: "s", turns: [.userText("go")], tools: []
        )
        guard case .functionCall(let call) = response else {
            XCTFail("Expected .functionCall, got \(response)"); return
        }
        XCTAssertEqual(call.name, "do_thing")
    }

    // MARK: - Error mapping

    func test401MapsToInvalidAPIKey() async {
        URLProtocolStub.queueHTTP(url: endpoint(), statusCode: 401, body: Data("nope".utf8))

        do {
            _ = try await client().sendToolMessage(
                systemPrompt: "s", turns: [.userText("h")], tools: []
            )
            XCTFail("Expected error")
        } catch let error as GeminiClient.GeminiError {
            XCTAssertEqual(error, .invalidAPIKey)
        } catch {
            XCTFail("Expected GeminiError, got \(error)")
        }
    }

    func test429MapsToRateLimitedWithRetryAfter() async {
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 429,
            headers: ["retry-after": "12"],
            body: Data()
        )

        do {
            _ = try await client().sendToolMessage(
                systemPrompt: "s", turns: [.userText("h")], tools: []
            )
            XCTFail("Expected error")
        } catch let error as GeminiClient.GeminiError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 12))
        } catch {
            XCTFail("Expected GeminiError, got \(error)")
        }
    }

    func test429WithoutRetryAfterDefaultsTo1Second() async {
        URLProtocolStub.queueHTTP(url: endpoint(), statusCode: 429)

        do {
            _ = try await client().sendToolMessage(
                systemPrompt: "s", turns: [.userText("h")], tools: []
            )
            XCTFail("Expected error")
        } catch let error as GeminiClient.GeminiError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 1))
        } catch {
            XCTFail("Expected GeminiError, got \(error)")
        }
    }

    func test500MapsToServerError() async {
        URLProtocolStub.queueHTTP(url: endpoint(), statusCode: 500, body: Data("internal".utf8))

        do {
            _ = try await client().sendToolMessage(
                systemPrompt: "s", turns: [.userText("h")], tools: []
            )
            XCTFail("Expected error")
        } catch let error as GeminiClient.GeminiError {
            if case .serverError(let body) = error {
                XCTAssertTrue(body.contains("internal"))
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Expected GeminiError, got \(error)")
        }
    }

    func testBlockedPromptMapsToServerError() async {
        let body = """
        {"promptFeedback":{"blockReason":"SAFETY"},"candidates":[]}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        do {
            _ = try await client().sendToolMessage(
                systemPrompt: "s", turns: [.userText("h")], tools: []
            )
            XCTFail("Expected error")
        } catch let error as GeminiClient.GeminiError {
            if case .serverError(let message) = error {
                XCTAssertTrue(message.contains("SAFETY"))
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Expected GeminiError, got \(error)")
        }
    }

    func testMissingCandidatesMapsToParseError() async {
        URLProtocolStub.queueHTTP(
            url: endpoint(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data("{}".utf8)
        )

        do {
            _ = try await client().sendToolMessage(
                systemPrompt: "s", turns: [.userText("h")], tools: []
            )
            XCTFail("Expected error")
        } catch let error as GeminiClient.GeminiError {
            if case .parseError = error { return }
            XCTFail("Expected .parseError, got \(error)")
        } catch {
            XCTFail("Expected GeminiError, got \(error)")
        }
    }

    // MARK: - GeminiTurn / ToolDeclaration value types

    func testGeminiToolDeclarationStoresFields() {
        let schema = Data(#"{"type":"object"}"#.utf8)
        let decl = GeminiToolDeclaration(
            name: "n", description: "d", parametersJSONSchema: schema
        )
        XCTAssertEqual(decl.name, "n")
        XCTAssertEqual(decl.description, "d")
        XCTAssertEqual(decl.parametersJSONSchema, schema)
    }

    func testGeminiFunctionCallEquatable() {
        let a = GeminiFunctionCall(name: "x", argumentsJSON: Data("{}".utf8))
        let b = GeminiFunctionCall(name: "x", argumentsJSON: Data("{}".utf8))
        let c = GeminiFunctionCall(name: "y", argumentsJSON: Data("{}".utf8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
