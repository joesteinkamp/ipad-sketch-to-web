import XCTest
@testable import SketchToWeb

final class GenerationHistoryTests: XCTestCase {

    // MARK: - Initial State

    func testEmptyInitialState() {
        let history = GenerationHistory()
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.count, 0)
        XCTAssertEqual(history.index, -1)
        XCTAssertNil(history.current)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    // MARK: - Push

    func testPushFromEmpty() {
        var history = GenerationHistory()
        let v1 = makeCode("v1")

        history.push(v1)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.index, 0)
        XCTAssertEqual(history.current, v1)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testPushAppendsAtEnd() {
        var history = GenerationHistory()
        history.push(makeCode("v1"))
        history.push(makeCode("v2"))

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.index, 1)
        XCTAssertEqual(history.current, makeCode("v2"))
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testPushAfterGoBackDiscardsForward() {
        var history = GenerationHistory()
        history.push(makeCode("v1"))
        history.push(makeCode("v2"))
        history.push(makeCode("v3"))
        history.goBack() // index = 1, current = v2
        history.goBack() // index = 0, current = v1

        history.push(makeCode("v4"))

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.versions, [makeCode("v1"), makeCode("v4")])
        XCTAssertEqual(history.index, 1)
        XCTAssertEqual(history.current, makeCode("v4"))
        XCTAssertFalse(history.canGoForward)
    }

    // MARK: - Navigation

    func testGoBackUpdatesIndexAndCurrent() {
        var history = GenerationHistory()
        history.push(makeCode("v1"))
        history.push(makeCode("v2"))

        let result = history.goBack()

        XCTAssertEqual(result, makeCode("v1"))
        XCTAssertEqual(history.index, 0)
        XCTAssertEqual(history.current, makeCode("v1"))
        XCTAssertTrue(history.canGoForward)
    }

    func testGoForwardUpdatesIndexAndCurrent() {
        var history = GenerationHistory()
        history.push(makeCode("v1"))
        history.push(makeCode("v2"))
        history.goBack()

        let result = history.goForward()

        XCTAssertEqual(result, makeCode("v2"))
        XCTAssertEqual(history.index, 1)
        XCTAssertEqual(history.current, makeCode("v2"))
        XCTAssertFalse(history.canGoForward)
    }

    func testGoBackAtBoundaryReturnsNil() {
        var history = GenerationHistory()
        history.push(makeCode("v1"))

        let result = history.goBack()

        XCTAssertNil(result)
        XCTAssertEqual(history.index, 0)
        XCTAssertEqual(history.current, makeCode("v1"))
    }

    func testGoForwardAtBoundaryReturnsNil() {
        var history = GenerationHistory()
        history.push(makeCode("v1"))
        history.push(makeCode("v2"))

        let result = history.goForward()

        XCTAssertNil(result)
        XCTAssertEqual(history.index, 1)
        XCTAssertEqual(history.current, makeCode("v2"))
    }

    func testGoBackOnEmptyReturnsNil() {
        var history = GenerationHistory()

        let result = history.goBack()

        XCTAssertNil(result)
        XCTAssertEqual(history.index, -1)
    }

    // MARK: - Helpers

    private func makeCode(_ label: String) -> GeneratedCode {
        GeneratedCode(htmlPreview: "<div>\(label)</div>", reactCode: "function \(label)() {}")
    }
}
