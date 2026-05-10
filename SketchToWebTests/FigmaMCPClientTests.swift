import XCTest
@testable import SketchToWeb

/// Tests `FigmaMCPClient`'s JSON-RPC envelope and SSE handling using
/// `URLProtocolStub` to mock the network. The client supports a custom
/// `URLSession`, which we use to wire the stub in cleanly.
final class FigmaMCPClientTests: XCTestCase {

    private let endpoint = URL(string: "https://mcp.figma.test/mcp")!

    private func makeClient(token: String = "test-token") -> FigmaMCPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        return FigmaMCPClient(
            endpoint: endpoint,
            tokenProvider: { token },
            session: session
        )
    }

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - tools/list (JSON body)

    func testListToolsParsesJSONResponse() async throws {
        let body = """
        {
          "jsonrpc": "2.0",
          "id": "1",
          "result": {
            "tools": [
              {"name": "get_design_context", "description": "Read design", "inputSchema": {"type": "object"}},
              {"name": "get_screenshot", "description": "Screenshot", "inputSchema": {}}
            ]
          }
        }
        """
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        let tools = try await makeClient().listTools()
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].name, "get_design_context")
        XCTAssertEqual(tools[0].description, "Read design")
        XCTAssertEqual(tools[1].name, "get_screenshot")
    }

    func testListToolsParsesSSEResponse() async throws {
        // Two events: a notification and the terminal result. The client should
        // pick the terminal one.
        let sse = """
        event: progress
        data: {"jsonrpc":"2.0","method":"progress","params":{"step":"warming"}}

        event: message
        data: {"jsonrpc":"2.0","id":"1","result":{"tools":[{"name":"x","description":"","inputSchema":{}}]}}

        """
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "text/event-stream"],
            body: Data(sse.utf8)
        )

        let tools = try await makeClient().listTools()
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "x")
    }

    // MARK: - Auth & error mapping

    func testHTTP401MapsToUnauthorized() async {
        URLProtocolStub.queueHTTP(url: endpoint, statusCode: 401, body: Data("nope".utf8))

        do {
            _ = try await makeClient().listTools()
            XCTFail("Expected unauthorized")
        } catch let error as FigmaMCPClient.MCPError {
            switch error {
            case .unauthorized: break
            default: XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Expected MCPError, got \(error)")
        }
    }

    func testHTTP403MapsToUnauthorized() async {
        URLProtocolStub.queueHTTP(url: endpoint, statusCode: 403)
        do {
            _ = try await makeClient().listTools()
            XCTFail("Expected unauthorized")
        } catch let error as FigmaMCPClient.MCPError {
            if case .unauthorized = error { return }
            XCTFail("Expected .unauthorized, got \(error)")
        } catch {
            XCTFail("Expected MCPError, got \(error)")
        }
    }

    func testHTTP500MapsToServerError() async {
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 500,
            body: Data("oops".utf8)
        )

        do {
            _ = try await makeClient().listTools()
            XCTFail("Expected server error")
        } catch let error as FigmaMCPClient.MCPError {
            if case .server(let code, let message) = error {
                XCTAssertEqual(code, 500)
                XCTAssertTrue(message.contains("oops"))
            } else {
                XCTFail("Expected .server, got \(error)")
            }
        } catch {
            XCTFail("Expected MCPError, got \(error)")
        }
    }

    func testJSONRPCErrorEnvelopeMapsToServerError() async {
        let body = """
        {"jsonrpc":"2.0","id":"1","error":{"code":-32602,"message":"Invalid params"}}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        do {
            _ = try await makeClient().listTools()
            XCTFail("Expected server error")
        } catch let error as FigmaMCPClient.MCPError {
            if case .server(let code, let message) = error {
                XCTAssertEqual(code, -32602)
                XCTAssertTrue(message.contains("Invalid params"))
            } else {
                XCTFail("Expected .server, got \(error)")
            }
        } catch {
            XCTFail("Expected MCPError, got \(error)")
        }
    }

    func testNonJSONResponseBodyMapsToParseError() async {
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data("not json".utf8)
        )

        do {
            _ = try await makeClient().listTools()
            XCTFail("Expected parse error")
        } catch let error as FigmaMCPClient.MCPError {
            if case .parse = error { return }
            XCTFail("Expected .parse, got \(error)")
        } catch {
            XCTFail("Expected MCPError, got \(error)")
        }
    }

    // MARK: - tools/call

    func testCallToolStitchesContentText() async throws {
        let body = """
        {"jsonrpc":"2.0","id":"1","result":{"content":[
          {"type":"text","text":"Hello"},
          {"type":"text","text":" world"},
          {"type":"image","data":"base64..."}
        ]}}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        let result = try await makeClient().callTool(name: "x", arguments: [:])
        XCTAssertEqual(result.textContent, "Hello\n world")
    }

    func testCallToolReturnsErrorWhenIsErrorTrue() async {
        let body = """
        {"jsonrpc":"2.0","id":"1","result":{"isError":true,"content":[{"type":"text","text":"boom"}]}}
        """
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        do {
            _ = try await makeClient().callTool(name: "x", arguments: [:])
            XCTFail("Expected toolError")
        } catch let error as FigmaMCPClient.MCPError {
            if case .toolError(let message) = error {
                XCTAssertTrue(message.contains("boom"))
            } else {
                XCTFail("Expected .toolError, got \(error)")
            }
        } catch {
            XCTFail("Expected MCPError, got \(error)")
        }
    }

    // MARK: - Request envelope

    func testOutgoingRequestUsesBearerAuthAndJSONRPC() async throws {
        let body = #"{"jsonrpc":"2.0","id":"1","result":{"tools":[]}}"#
        URLProtocolStub.queueHTTP(
            url: endpoint,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        )

        _ = try await makeClient(token: "abc-123").listTools()

        let captured = URLProtocolStub.drainCapturedRequests()
        XCTAssertEqual(captured.count, 1)
        let request = captured[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        // URLProtocol's request loses the body in some configurations; tolerate
        // missing body and assert only when present.
        if let bodyData = request.httpBody ?? request.httpBodyStream.flatMap(Self.readAll) {
            let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
            XCTAssertEqual(json?["method"] as? String, "tools/list")
        }
    }

    // MARK: - ToolDescription Equatable (name + description only)

    func testToolDescriptionEqualityIgnoresInputSchema() {
        let a = FigmaMCPClient.ToolDescription(
            name: "x", description: "d", inputSchema: ["type": "object"]
        )
        let b = FigmaMCPClient.ToolDescription(
            name: "x", description: "d", inputSchema: [:]
        )
        XCTAssertEqual(a, b, "Equatable is documented to compare name + description only")

        let c = FigmaMCPClient.ToolDescription(
            name: "y", description: "d", inputSchema: ["type": "object"]
        )
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Helpers

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
