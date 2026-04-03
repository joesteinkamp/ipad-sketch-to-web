import XCTest
@testable import SketchToWeb

@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let state = AppState()
        XCTAssertFalse(state.isConverting)
        XCTAssertFalse(state.isRefining)
        XCTAssertNil(state.conversionError)
        XCTAssertNil(state.generatedResult)
        XCTAssertNil(state.streamingText)
        XCTAssertTrue(state.generationHistory.isEmpty)
        XCTAssertEqual(state.generationHistoryIndex, -1)
    }

    // MARK: - History Navigation

    func testCanGoBackReturnsFalseWhenEmpty() {
        let state = AppState()
        XCTAssertFalse(state.canGoBack)
    }

    func testCanGoForwardReturnsFalseWhenEmpty() {
        let state = AppState()
        XCTAssertFalse(state.canGoForward)
    }

    func testCanGoBackReturnsFalseAtFirstItem() {
        let state = AppState()
        state.generationHistory = [makeCode("v1")]
        state.generationHistoryIndex = 0
        XCTAssertFalse(state.canGoBack)
    }

    func testCanGoBackReturnsTrueAtSecondItem() {
        let state = AppState()
        state.generationHistory = [makeCode("v1"), makeCode("v2")]
        state.generationHistoryIndex = 1
        XCTAssertTrue(state.canGoBack)
    }

    func testCanGoForwardReturnsTrueWhenNotAtEnd() {
        let state = AppState()
        state.generationHistory = [makeCode("v1"), makeCode("v2")]
        state.generationHistoryIndex = 0
        XCTAssertTrue(state.canGoForward)
    }

    func testCanGoForwardReturnsFalseAtEnd() {
        let state = AppState()
        state.generationHistory = [makeCode("v1"), makeCode("v2")]
        state.generationHistoryIndex = 1
        XCTAssertFalse(state.canGoForward)
    }

    func testGoBackUpdatesIndexAndResult() {
        let state = AppState()
        let v1 = makeCode("v1")
        let v2 = makeCode("v2")
        state.generationHistory = [v1, v2]
        state.generationHistoryIndex = 1
        state.generatedResult = v2

        state.goBack()

        XCTAssertEqual(state.generationHistoryIndex, 0)
        XCTAssertEqual(state.generatedResult, v1)
    }

    func testGoForwardUpdatesIndexAndResult() {
        let state = AppState()
        let v1 = makeCode("v1")
        let v2 = makeCode("v2")
        state.generationHistory = [v1, v2]
        state.generationHistoryIndex = 0
        state.generatedResult = v1

        state.goForward()

        XCTAssertEqual(state.generationHistoryIndex, 1)
        XCTAssertEqual(state.generatedResult, v2)
    }

    func testGoBackDoesNothingWhenCantGoBack() {
        let state = AppState()
        let v1 = makeCode("v1")
        state.generationHistory = [v1]
        state.generationHistoryIndex = 0
        state.generatedResult = v1

        state.goBack()

        XCTAssertEqual(state.generationHistoryIndex, 0)
        XCTAssertEqual(state.generatedResult, v1)
    }

    func testGoForwardDoesNothingWhenCantGoForward() {
        let state = AppState()
        let v1 = makeCode("v1")
        state.generationHistory = [v1]
        state.generationHistoryIndex = 0
        state.generatedResult = v1

        state.goForward()

        XCTAssertEqual(state.generationHistoryIndex, 0)
        XCTAssertEqual(state.generatedResult, v1)
    }

    // MARK: - Convert Guard

    func testConvertDrawingGuardsAgainstDoubleConvert() {
        let state = AppState()
        state.isConverting = true
        state.convertDrawing()
        // Should return early, isConverting should still be true (not reset).
        XCTAssertTrue(state.isConverting)
    }

    // MARK: - Refine Guard

    func testRefineGuardsWhenAlreadyRefining() {
        let state = AppState()
        state.isRefining = true
        state.generatedResult = makeCode("v1")
        state.refineResult(annotationImage: Data([1, 2, 3]), canvasSize: CGSize(width: 100, height: 100))
        // Should return early.
        XCTAssertTrue(state.isRefining)
    }

    func testRefineGuardsWhenNoResult() {
        let state = AppState()
        state.generatedResult = nil
        state.refineResult(annotationImage: Data([1, 2, 3]), canvasSize: CGSize(width: 100, height: 100))
        // Should not start refining.
        XCTAssertFalse(state.isRefining)
    }

    // MARK: - Helpers

    private func makeCode(_ label: String) -> GeneratedCode {
        GeneratedCode(htmlPreview: "<div>\(label)</div>", reactCode: "function \(label)() {}")
    }
}
