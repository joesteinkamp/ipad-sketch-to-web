import Foundation

// MARK: - Public Types

/// A function (tool) declaration to surface to Gemini's function-calling API.
/// `parametersJSONSchema` is a JSON Schema document encoded as JSON bytes —
/// typically forwarded directly from an MCP server's `inputSchema`.
struct GeminiToolDeclaration: Sendable {
    let name: String
    let description: String
    let parametersJSONSchema: Data

    init(name: String, description: String, parametersJSONSchema: Data) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
    }
}

/// A function call emitted by the model. `argumentsJSON` is the raw JSON-encoded
/// argument object from Gemini's response.
struct GeminiFunctionCall: Sendable, Equatable {
    let name: String
    let argumentsJSON: Data
}

/// One turn in a Gemini conversation that uses function calling.
enum GeminiTurn: Sendable {
    case userText(String)
    case userImage(Data, mimeType: String)
    case modelText(String)
    case modelFunctionCall(GeminiFunctionCall)
    case userFunctionResponse(name: String, responseJSON: Data)
}

/// The terminal result of a single Gemini call when tools are attached.
enum GeminiToolResponse: Sendable {
    case text(String)
    case functionCall(GeminiFunctionCall)
}

// MARK: - GeminiClient extension

extension GeminiClient {

    /// Sends a multi-turn conversation to Gemini with attached tools, returning
    /// either a final text response or a single function call to execute. The
    /// caller is responsible for executing the tool and looping back with the
    /// result appended as `userFunctionResponse`.
    func sendToolMessage(
        systemPrompt: String,
        turns: [GeminiTurn],
        tools: [GeminiToolDeclaration]
    ) async throws -> GeminiToolResponse {
        let body = try buildFunctionCallingBody(
            systemPrompt: systemPrompt,
            turns: turns,
            tools: tools
        )
        let endpointURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.networkError(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200:
            return try parseToolResponse(data)
        case 401, 403:
            throw GeminiError.invalidAPIKey
        case 429:
            let retryAfter: TimeInterval
            if let header = http.value(forHTTPHeaderField: "retry-after"),
               let seconds = TimeInterval(header) {
                retryAfter = seconds
            } else {
                retryAfter = 1.0
            }
            throw GeminiError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GeminiError.serverError(body)
        }
    }

    // MARK: - Body Construction

    private func buildFunctionCallingBody(
        systemPrompt: String,
        turns: [GeminiTurn],
        tools: [GeminiToolDeclaration]
    ) throws -> [String: Any] {
        var contents: [[String: Any]] = []

        for turn in turns {
            switch turn {
            case .userText(let text):
                contents.append([
                    "role": "user",
                    "parts": [["text": text]]
                ])
            case .userImage(let data, let mimeType):
                contents.append([
                    "role": "user",
                    "parts": [[
                        "inlineData": [
                            "mimeType": mimeType,
                            "data": data.base64EncodedString()
                        ]
                    ]]
                ])
            case .modelText(let text):
                contents.append([
                    "role": "model",
                    "parts": [["text": text]]
                ])
            case .modelFunctionCall(let call):
                let args = (try? JSONSerialization.jsonObject(with: call.argumentsJSON)) ?? [:]
                contents.append([
                    "role": "model",
                    "parts": [[
                        "functionCall": [
                            "name": call.name,
                            "args": args
                        ]
                    ]]
                ])
            case .userFunctionResponse(let name, let responseJSON):
                let response = (try? JSONSerialization.jsonObject(with: responseJSON)) ?? [:]
                contents.append([
                    "role": "user",
                    "parts": [[
                        "functionResponse": [
                            "name": name,
                            "response": response
                        ]
                    ]]
                ])
            }
        }

        let functionDeclarations: [[String: Any]] = try tools.map { tool in
            let schema = (try? JSONSerialization.jsonObject(with: tool.parametersJSONSchema)) ?? [:]
            return [
                "name": tool.name,
                "description": tool.description,
                "parameters": schema
            ]
        }

        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 8192,
                "temperature": 0.2
            ]
        ]
        if !functionDeclarations.isEmpty {
            body["tools"] = [["functionDeclarations": functionDeclarations]]
        }
        return body
    }

    // MARK: - Response Parsing

    private func parseToolResponse(_ data: Data) throws -> GeminiToolResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.parseError("Response is not JSON")
        }
        if let promptFeedback = json["promptFeedback"] as? [String: Any],
           let blockReason = promptFeedback["blockReason"] as? String,
           (json["candidates"] as? [[String: Any]])?.isEmpty ?? true {
            throw GeminiError.serverError("Request blocked: \(blockReason)")
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.parseError("Response missing candidates[0].content.parts")
        }

        // Prefer a function call if any part contains one.
        for part in parts {
            if let call = part["functionCall"] as? [String: Any],
               let name = call["name"] as? String {
                let args = call["args"] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
                return .functionCall(GeminiFunctionCall(name: name, argumentsJSON: argsData))
            }
        }

        // Otherwise concatenate any text parts.
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return .text(text)
    }
}
