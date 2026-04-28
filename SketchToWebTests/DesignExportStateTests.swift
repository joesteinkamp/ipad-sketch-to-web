import XCTest
@testable import SketchToWeb

final class DesignExportStateTests: XCTestCase {

    func testIsTerminalForCompleted() {
        XCTAssertTrue(DesignExportState.completed(fileURL: nil).isTerminal)
        XCTAssertTrue(DesignExportState.completed(fileURL: URL(string: "https://figma.com/file/abc")).isTerminal)
    }

    func testIsTerminalForFailed() {
        XCTAssertTrue(DesignExportState.failed(message: "boom").isTerminal)
    }

    func testIsNotTerminalForConnecting() {
        XCTAssertFalse(DesignExportState.connecting.isTerminal)
    }

    func testIsNotTerminalForWorking() {
        XCTAssertFalse(DesignExportState.working(step: "Creating frame").isTerminal)
    }

    func testEquality() {
        XCTAssertEqual(DesignExportState.connecting, DesignExportState.connecting)
        XCTAssertEqual(
            DesignExportState.working(step: "x"),
            DesignExportState.working(step: "x")
        )
        XCTAssertNotEqual(
            DesignExportState.working(step: "x"),
            DesignExportState.working(step: "y")
        )
    }
}
