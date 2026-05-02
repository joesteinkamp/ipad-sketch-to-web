import XCTest
import PencilKit
@testable import SketchToWeb

@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let state = AppState()
        XCTAssertFalse(state.isConverting)
        XCTAssertFalse(state.isRefining)
        XCTAssertNil(state.error)
        XCTAssertNil(state.conversionError)
        XCTAssertNil(state.generatedResult)
        XCTAssertNil(state.streamingText)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.generationHistory, [])
        XCTAssertEqual(state.generationHistoryIndex, -1)
        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
    }

    // MARK: - conversionError Bridge

    func testConversionErrorReflectsTypedError() {
        let state = AppState()
        state.error = .apiKeyMissing
        XCTAssertNotNil(state.conversionError)
        XCTAssertTrue(state.conversionError!.contains("API key"))
    }

    func testClearingConversionErrorClearsTypedError() {
        let state = AppState()
        state.error = .network("offline")
        XCTAssertNotNil(state.conversionError)

        state.conversionError = nil

        XCTAssertNil(state.error)
        XCTAssertNil(state.conversionError)
    }

    // MARK: - History Bridges

    func testCanGoBackForwardDelegateToHistory() {
        let state = makeStateWithMockClient(MockGeminiAPI())
        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
        // Direct navigation works through the underlying history; covered fully in
        // GenerationHistoryTests. Here we just verify the AppState delegation surface.
        state.goBack()  // no-op when empty
        state.goForward()  // no-op when empty
        XCTAssertTrue(state.history.isEmpty)
    }

    // MARK: - Convert Guard

    func testConvertDrawingGuardsAgainstDoubleConvert() {
        let state = AppState()
        state.isConverting = true
        state.convertDrawing()
        XCTAssertTrue(state.isConverting, "Second call should return early without resetting state")
    }

    // MARK: - Convert: Missing API Key

    func testConvertDrawingMissingAPIKeyEmitsAppError() async {
        let state = makeStateWithMockClient(MockGeminiAPI(), apiKey: nil)
        state.convertDrawing()

        await waitForCondition { !state.isConverting }

        XCTAssertEqual(state.error, .apiKeyMissing)
        XCTAssertNil(state.streamingText)
    }

    // MARK: - Refine Guards

    func testRefineGuardsWhenAlreadyRefining() {
        let state = AppState()
        state.isRefining = true
        state.generatedResult = makeCode("v1")
        state.refineResult(annotationImage: Data([1, 2, 3]), canvasSize: CGSize(width: 100, height: 100))
        XCTAssertTrue(state.isRefining)
    }

    func testRefineGuardsWhenNoResult() {
        let state = AppState()
        state.generatedResult = nil
        state.refineResult(annotationImage: Data([1, 2, 3]), canvasSize: CGSize(width: 100, height: 100))
        XCTAssertFalse(state.isRefining)
    }

    // MARK: - Refine: Happy Path

    func testRefineSuccessPushesOntoHistoryAndClearsError() async {
        let mock = MockGeminiAPI()
        await mock.setNextResponse(.success(
            #"{"htmlPreview": "<div>refined</div>", "reactCode": "function R() {}"}"#
        ))
        let state = makeStateWithMockClient(mock)
        state.error = .network("stale error")
        state.generatedResult = makeCode("v0")

        state.refineResult(
            annotationImage: Data([1, 2, 3]),
            canvasSize: CGSize(width: 200, height: 200)
        )

        await waitForCondition { !state.isRefining }

        XCTAssertNil(state.error, "Successful refine should clear prior error")
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history.current?.htmlPreview, "<div>refined</div>")
        XCTAssertEqual(state.generatedResult?.htmlPreview, "<div>refined</div>")
    }

    // MARK: - Refine: Error Paths

    func testRefineMissingAPIKeyEmitsAppError() async {
        let state = makeStateWithMockClient(MockGeminiAPI(), apiKey: nil)
        state.generatedResult = makeCode("v0")

        state.refineResult(
            annotationImage: Data([1, 2, 3]),
            canvasSize: CGSize(width: 100, height: 100)
        )

        await waitForCondition { !state.isRefining }

        XCTAssertEqual(state.error, .apiKeyMissing)
    }

    func testRefineEmptyAnnotationEmitsImageEmpty() async {
        let state = makeStateWithMockClient(MockGeminiAPI())
        state.generatedResult = makeCode("v0")

        state.refineResult(
            annotationImage: Data(),
            canvasSize: CGSize(width: 100, height: 100)
        )

        await waitForCondition { !state.isRefining }

        XCTAssertEqual(state.error, .imageEmpty)
    }

    func testRefineMapsRateLimitError() async {
        let mock = MockGeminiAPI()
        await mock.setNextResponse(.failure(GeminiClient.GeminiError.rateLimited(retryAfter: 12)))
        let state = makeStateWithMockClient(mock)
        state.generatedResult = makeCode("v0")

        state.refineResult(
            annotationImage: Data([1, 2, 3]),
            canvasSize: CGSize(width: 100, height: 100)
        )

        await waitForCondition { !state.isRefining }

        XCTAssertEqual(state.error, .rateLimited(retryAfter: 12))
    }

    // MARK: - Helpers

    private func makeCode(_ label: String) -> GeneratedCode {
        GeneratedCode(htmlPreview: "<div>\(label)</div>", reactCode: "function \(label)() {}")
    }

    /// Constructs an AppState wired to use the supplied mock for both pipelines.
    /// `apiKey` defaults to a non-empty fake; pass `nil` to simulate a missing key.
    private func makeStateWithMockClient(_ mock: MockGeminiAPI, apiKey: String? = "test-key") -> AppState {
        AppState(
            makeConversionPipeline: { _, _ in AIConversionPipeline(client: mock) },
            makeRefinementPipeline: { _, _ in RefinementPipeline(client: mock) },
            apiKeyProvider: { apiKey }
        )
    }

    /// Polls a condition on the main actor with a short timeout. Used to wait for
    /// `Task { ... }`-backed methods on AppState to finish.
    private func waitForCondition(
        timeout: TimeInterval = 2,
        _ check: @MainActor @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !check() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
    }
}
