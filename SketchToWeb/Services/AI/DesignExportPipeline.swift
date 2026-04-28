import Foundation

/// Orchestrates handing the original sketch + generated code off to a remote
/// design tool's MCP server, using Gemini as the agent that interprets the
/// brief and drives the destination's tool calls.
///
/// Flow:
/// 1. Resolve OAuth bearer for the destination.
/// 2. Connect to the destination's MCP, list its tools.
/// 3. Forward those tools to Gemini as function declarations along with the
///    sketch image, generated code, and a directive prompt.
/// 4. Loop: if Gemini returns a function call, execute it against the MCP and
///    feed the result back. Stop when Gemini returns terminal text (or hits the
///    safety limit on rounds).
final class DesignExportPipeline: Sendable {

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case notConnected(DesignDestination)
        case geminiKeyMissing
        case maxRoundsExceeded
        case tooManyToolCalls

        var errorDescription: String? {
            switch self {
            case .notConnected(let destination):
                return "Not signed in to \(destination.displayName). Connect in Settings first."
            case .geminiKeyMissing:
                return "Gemini API key is not configured. Please add your key in Settings."
            case .maxRoundsExceeded:
                return "Design export took too long and was stopped."
            case .tooManyToolCalls:
                return "Design tool returned too many calls; aborting."
            }
        }
    }

    // MARK: - Properties

    private let geminiAPIKey: String
    private let geminiModel: String
    private let destination: DesignDestination
    private let mcpClient: FigmaMCPClient
    private let maxRounds: Int

    // MARK: - Initialization

    /// - Parameters:
    ///   - destination: Which design tool to export to (Figma today).
    ///   - geminiAPIKey: User's Gemini API key.
    ///   - geminiModel: Gemini model to drive the orchestration.
    ///   - mcpClient: Override for tests; defaults to a live client wired to the
    ///     destination's endpoint and `FigmaOAuth.shared`.
    ///   - maxRounds: Safety limit on tool-call rounds. Defaults to 24.
    init(
        destination: DesignDestination,
        geminiAPIKey: String,
        geminiModel: String,
        mcpClient: FigmaMCPClient? = nil,
        maxRounds: Int = 24
    ) {
        self.destination = destination
        self.geminiAPIKey = geminiAPIKey
        self.geminiModel = geminiModel
        self.maxRounds = maxRounds
        self.mcpClient = mcpClient ?? FigmaMCPClient(
            endpoint: destination.mcpEndpoint,
            tokenProvider: { @Sendable in
                try await FigmaOAuth.shared.currentAccessToken()
            }
        )
    }

    // MARK: - Run

    /// Streams `DesignExportState` values as the export progresses.
    ///
    /// - Parameters:
    ///   - sketchPNG: PNG of the original PencilKit drawing on a white background.
    ///   - generatedCode: The HTML/React already produced by the conversion pipeline.
    ///   - userInstruction: Optional free-form note from the user (e.g. "Match my
    ///     design system", "Group into a single frame").
    func run(
        sketchPNG: Data,
        generatedCode: GeneratedCode,
        userInstruction: String? = nil
    ) -> AsyncThrowingStream<DesignExportState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.connecting)

                    let tools = try await mcpClient.listTools()
                    let toolDeclarations = tools.map { tool -> GeminiToolDeclaration in
                        let schemaData = (try? JSONSerialization.data(withJSONObject: tool.inputSchema))
                            ?? Data("{}".utf8)
                        return GeminiToolDeclaration(
                            name: tool.name,
                            description: tool.description,
                            parametersJSONSchema: schemaData
                        )
                    }

                    let gemini = GeminiClient(apiKey: geminiAPIKey, model: geminiModel)
                    let systemPrompt = Self.buildSystemPrompt(destination: destination)
                    let userPrompt = Self.buildUserPrompt(
                        generatedCode: generatedCode,
                        userInstruction: userInstruction
                    )

                    var turns: [GeminiTurn] = [
                        .userImage(sketchPNG, mimeType: "image/png"),
                        .userText(userPrompt)
                    ]

                    var fileURL: URL?

                    for round in 0..<maxRounds {
                        if Task.isCancelled { break }

                        let response = try await gemini.sendToolMessage(
                            systemPrompt: systemPrompt,
                            turns: turns,
                            tools: toolDeclarations
                        )

                        switch response {
                        case .text(let finalText):
                            if let url = Self.extractFigmaURL(from: finalText) {
                                fileURL = url
                            }
                            continuation.yield(.completed(fileURL: fileURL))
                            continuation.finish()
                            return

                        case .functionCall(let call):
                            continuation.yield(.working(step: Self.describeStep(for: call, round: round)))

                            let args = (try? JSONSerialization.jsonObject(with: call.argumentsJSON)) as? [String: Any] ?? [:]
                            let result: FigmaMCPClient.ToolCallResult
                            do {
                                result = try await mcpClient.callTool(name: call.name, arguments: args)
                            } catch let error as FigmaMCPClient.MCPError {
                                // Surface tool errors back to Gemini so it can recover or stop.
                                let errorJSON = try JSONSerialization.data(withJSONObject: [
                                    "error": error.localizedDescription
                                ])
                                turns.append(.modelFunctionCall(call))
                                turns.append(.userFunctionResponse(name: call.name, responseJSON: errorJSON))
                                continue
                            }

                            if let url = Self.extractFigmaURL(from: result.textContent) {
                                fileURL = url
                            }

                            let responseJSON = try JSONSerialization.data(withJSONObject: [
                                "content": result.textContent
                            ])
                            turns.append(.modelFunctionCall(call))
                            turns.append(.userFunctionResponse(name: call.name, responseJSON: responseJSON))
                        }
                    }

                    throw ExportError.maxRoundsExceeded
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    continuation.yield(.failed(message: message))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Prompt Construction

    static func buildSystemPrompt(destination: DesignDestination) -> String {
        """
        You are an assistant that takes a hand-drawn UI sketch (image attached) plus its \
        generated HTML and React code, and reconstructs it as an editable design in \
        \(destination.displayName) by calling the available tools.

        Guidelines:
        - The sketch shows the user's intent; the HTML/React shows the realized layout. \
          Treat the sketch as authoritative for layout intent and the code as authoritative \
          for component identity, copy, and styling details.
        - Use the destination's auto-layout / frame primitives so the result is editable.
        - Prefer the destination's design-system components when an obvious match exists. \
          Otherwise build the layout from primitives (frames, text, rectangles).
        - Group everything into a single named frame so the user can find it easily.
        - When you finish, respond with a short confirmation that includes the URL of the \
          \(destination.displayName) file or frame you created, if the tool returns one.
        - Do not ask the user clarifying questions; make reasonable choices and proceed.
        """
    }

    static func buildUserPrompt(generatedCode: GeneratedCode, userInstruction: String?) -> String {
        let extra = userInstruction.flatMap { $0.isEmpty ? nil : "User note: \($0)\n\n" } ?? ""
        return """
        \(extra)Build the design that this sketch represents in the design tool.

        # Generated React code
        ```jsx
        \(generatedCode.reactCode)
        ```

        # Generated HTML
        ```html
        \(generatedCode.htmlPreview)
        ```
        """
    }

    // MARK: - Helpers

    static func extractFigmaURL(from text: String) -> URL? {
        let pattern = #"https?://(?:www\.)?figma\.com/[^\s)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return URL(string: String(text[matchRange]))
    }

    static func describeStep(for call: GeminiFunctionCall, round: Int) -> String {
        let humanized = call.name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return "Step \(round + 1): \(humanized)"
    }
}
