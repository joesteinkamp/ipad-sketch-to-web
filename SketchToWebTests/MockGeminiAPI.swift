import Foundation
@testable import SketchToWeb

/// Records calls and returns scripted responses for `GeminiAPI`.
///
/// Tests configure `nextResponse` (or `responseScript`) before exercising the
/// pipeline, then inspect the recorded calls afterward to verify the pipeline
/// passed the right prompts and image data.
actor MockGeminiAPI: GeminiAPI {
    enum ScriptedResponse: Sendable {
        case success(String)
        case failure(any Error & Sendable)
    }

    struct ImageCall: Sendable, Equatable {
        let systemPrompt: String
        let imageData: Data
        let userText: String
    }

    struct TextCall: Sendable, Equatable {
        let systemPrompt: String
        let userText: String
    }

    private(set) var imageCalls: [ImageCall] = []
    private(set) var textCalls: [TextCall] = []

    /// Default response used when `responseScript` is empty. Defaults to a
    /// minimal valid `GeneratedCode` JSON payload.
    var nextResponse: ScriptedResponse = .success(
        #"{"htmlPreview": "<div>mock</div>", "reactCode": "function Mock() { return null; }"}"#
    )

    /// Optional FIFO queue of responses. When non-empty, each call pops the
    /// next one. When empty, falls back to `nextResponse`.
    var responseScript: [ScriptedResponse] = []

    func setNextResponse(_ response: ScriptedResponse) {
        nextResponse = response
    }

    func setResponseScript(_ script: [ScriptedResponse]) {
        responseScript = script
    }

    func sendMessage(systemPrompt: String, imageData: Data, userText: String) async throws -> String {
        imageCalls.append(ImageCall(systemPrompt: systemPrompt, imageData: imageData, userText: userText))
        return try popResponse()
    }

    func sendTextMessage(systemPrompt: String, userText: String) async throws -> String {
        textCalls.append(TextCall(systemPrompt: systemPrompt, userText: userText))
        return try popResponse()
    }

    private func popResponse() throws -> String {
        let response: ScriptedResponse
        if !responseScript.isEmpty {
            response = responseScript.removeFirst()
        } else {
            response = nextResponse
        }
        switch response {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
