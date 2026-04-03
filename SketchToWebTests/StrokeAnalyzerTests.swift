import XCTest
import PencilKit
@testable import SketchToWeb

final class StrokeAnalyzerTests: XCTestCase {

    private let canvasSize = CGSize(width: 1024, height: 768)

    // MARK: - No New Strokes

    func testAnalyzeReturnsEmptyWhenNoNewStrokes() {
        let drawing = PKDrawing()
        let result = StrokeAnalyzer.analyzeNewStrokes(
            previous: drawing,
            current: drawing,
            canvasSize: canvasSize
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeReturnsEmptyWhenStrokesRemoved() {
        // If current has fewer strokes than previous, returns empty.
        let stroke = makeStroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50))
        var previous = PKDrawing()
        previous.strokes.append(stroke)
        let current = PKDrawing()

        let result = StrokeAnalyzer.analyzeNewStrokes(
            previous: previous,
            current: current,
            canvasSize: canvasSize
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Shape Types

    func testRecognizedShapeHasUniqueID() {
        let shape1 = StrokeAnalyzer.RecognizedShape(type: .button, bounds: .zero, confidence: 0.5)
        let shape2 = StrokeAnalyzer.RecognizedShape(type: .button, bounds: .zero, confidence: 0.5)
        XCTAssertNotEqual(shape1.id, shape2.id)
    }

    func testShapeTypesHaveRawValues() {
        XCTAssertEqual(StrokeAnalyzer.ShapeType.button.rawValue, "Button")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.input.rawValue, "Input")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.card.rawValue, "Card")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.checkbox.rawValue, "Checkbox")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.radio.rawValue, "Radio")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.separator.rawValue, "Separator")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.navigation.rawValue, "Navigation")
        XCTAssertEqual(StrokeAnalyzer.ShapeType.unknown.rawValue, "Unknown")
    }

    func testAllShapeTypeCases() {
        XCTAssertEqual(StrokeAnalyzer.ShapeType.allCases.count, 8)
    }

    // MARK: - Helpers

    /// Creates a simple two-point PKStroke for testing.
    private func makeStroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        let points = [
            PKStrokePoint(location: start, timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: end, timeOffset: 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: ink, path: path)
    }
}
