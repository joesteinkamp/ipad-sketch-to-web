import Foundation

/// A minimal MCP / JSON-RPC 2.0 client for talking to a remote MCP server such as
/// Figma's at `https://mcp.figma.com/mcp`. Supports `initialize`, `tools/list`,
/// and `tools/call`. Authenticates via a bearer token (sourced from
/// `FigmaOAuth.currentAccessToken()`).
final class FigmaMCPClient: Sendable {

    // MARK: - Errors

    enum MCPError: LocalizedError {
        case unauthorized
        case server(code: Int, message: String)
        case network(Error)
        case parse(String)
        case toolError(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Figma rejected the access token. Please reconnect in Settings."
            case .server(let code, let message):
                return "Figma MCP error (\(code)): \(message)"
            case .network(let error):
                return "Network error talking to Figma MCP: \(error.localizedDescription)"
            case .parse(let message):
                return "Failed to parse Figma MCP response: \(message)"
            case .toolError(let message):
                return "Figma tool returned an error: \(message)"
            }
        }
    }

    // MARK: - Public Types

    /// Description of an MCP tool advertised by the server, suitable for forwarding
    /// to an LLM's function-calling API.
    struct ToolDescription: Sendable, Equatable {
        let name: String
        let description: String
        /// Raw JSON Schema for the tool's input parameters.
        let inputSchema: [String: Any]

        static func == (lhs: ToolDescription, rhs: ToolDescription) -> Bool {
            lhs.name == rhs.name && lhs.description == rhs.description
        }
    }

    /// Result of a successful `tools/call` invocation.
    struct ToolCallResult: Sendable {
        /// Stitched textual content from the response.
        let textContent: String
        /// The raw JSON-RPC `result` payload (may include structured fields).
        let raw: [String: Any]
    }

    // MARK: - Properties

    let endpoint: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () async throws -> String

    // MARK: - Initialization

    /// - Parameters:
    ///   - endpoint: MCP HTTP endpoint (e.g. `https://mcp.figma.com/mcp`).
    ///   - tokenProvider: Closure that returns a fresh bearer token. Typically
    ///     wraps `FigmaOAuth.shared.currentAccessToken()`.
    ///   - session: Optional URLSession override; defaults to a 120s-timeout session.
    init(
        endpoint: URL,
        tokenProvider: @escaping @Sendable () async throws -> String,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - JSON-RPC Methods

    /// Lists the tools exposed by the MCP server.
    func listTools() async throws -> [ToolDescription] {
        let result = try await sendRPC(method: "tools/list", params: [:])
        guard let toolsArray = result["tools"] as? [[String: Any]] else {
            throw MCPError.parse("Missing 'tools' array in tools/list response")
        }
        return toolsArray.compactMap { dict -> ToolDescription? in
            guard let name = dict["name"] as? String else { return nil }
            let description = (dict["description"] as? String) ?? ""
            let inputSchema = (dict["inputSchema"] as? [String: Any]) ?? [:]
            return ToolDescription(name: name, description: description, inputSchema: inputSchema)
        }
    }

    /// Invokes a tool by name with the given arguments.
    func callTool(name: String, arguments: [String: Any]) async throws -> ToolCallResult {
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        let result = try await sendRPC(method: "tools/call", params: params)

        if let isError = result["isError"] as? Bool, isError {
            let message = extractText(from: result) ?? "Unknown tool error"
            throw MCPError.toolError(message)
        }

        let text = extractText(from: result) ?? ""
        return ToolCallResult(textContent: text, raw: result)
    }

    // MARK: - JSON-RPC Transport

    private func sendRPC(method: String, params: [String: Any]) async throws -> [String: Any] {
        let token = try await tokenProvider()

        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MCPError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MCPError.parse("Invalid HTTP response")
        }

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw MCPError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MCPError.server(code: http.statusCode, message: body)
        }

        let payload: [String: Any]
        if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("text/event-stream") {
            payload = try parseSSE(data)
        } else {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPError.parse("Body is not JSON")
            }
            payload = json
        }

        if let error = payload["error"] as? [String: Any] {
            let code = (error["code"] as? Int) ?? 0
            let message = (error["message"] as? String) ?? "Unknown JSON-RPC error"
            throw MCPError.server(code: code, message: message)
        }

        guard let result = payload["result"] as? [String: Any] else {
            throw MCPError.parse("Response missing 'result'")
        }
        return result
    }

    /// Parses a single-event SSE response body into the JSON-RPC envelope. Picks
    /// the last `data:` chunk so streaming responses with progress + final result
    /// resolve to the terminal payload.
    private func parseSSE(_ data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPError.parse("SSE body is not UTF-8")
        }
        var lastJSON: [String: Any]?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let chunkData = jsonText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any] else {
                continue
            }
            // A JSON-RPC response carries either `result` or `error`. Skip notifications.
            if json["result"] != nil || json["error"] != nil {
                lastJSON = json
            }
        }
        guard let payload = lastJSON else {
            throw MCPError.parse("No JSON-RPC response in SSE stream")
        }
        return payload
    }

    /// Extracts a stitched text string from a `tools/call` result's `content` array.
    private func extractText(from result: [String: Any]) -> String? {
        guard let content = result["content"] as? [[String: Any]] else { return nil }
        let parts: [String] = content.compactMap { item in
            if let type = item["type"] as? String, type == "text",
               let text = item["text"] as? String {
                return text
            }
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
