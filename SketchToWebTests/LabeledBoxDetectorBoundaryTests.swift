import XCTest
import PencilKit
@testable import SketchToWeb

/// Boundary-condition tests for `LabeledBoxDetector`. The geometry-only path
/// (`assignInteriorStrokes`) is `private`, so we exercise the public
/// `detect(...)` entrypoint with degenerate inputs that don't require Vision
/// OCR. Deeper geometry coverage would need either an internal-visibility
/// shim or seeded Vision fixtures — see the test methods marked `XCTSkip`.
@MainActor
final class LabeledBoxDetectorBoundaryTests: XCTestCase {

    private let canvas = CGSize(width: 1024, height: 768)

    // MARK: - Public entrypoint short-circuits

    func testEmptyDrawingReturnsEmpty() async {
        let labels = await LabeledBoxDetector.detect(
            drawing: PKDrawing(),
            canvasSize: canvas,
            catalog: []
        )
        XCTAssertTrue(labels.isEmpty)
    }

    func testSingleStrokeReturnsEmpty() async {
        // The function early-returns when strokes.count < 2; no container can
        // enclose anything else.
        var drawing = PKDrawing()
        drawing.strokes.append(makeLineStroke(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 200, y: 100)
        ))
        let labels = await LabeledBoxDetector.detect(
            drawing: drawing, canvasSize: canvas, catalog: []
        )
        XCTAssertTrue(labels.isEmpty)
    }

    func testTwoNonOverlappingStrokesReturnsEmpty() async {
        // Two strokes that don't enclose each other → no containers, no labels.
        var drawing = PKDrawing()
        drawing.strokes.append(makeLineStroke(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0)
        ))
        drawing.strokes.append(makeLineStroke(
            from: CGPoint(x: 500, y: 500), to: CGPoint(x: 550, y: 500)
        ))
        let labels = await LabeledBoxDetector.detect(
            drawing: drawing, canvasSize: canvas, catalog: []
        )
        XCTAssertTrue(labels.isEmpty)
    }

    /// Gibberish strokes inside a box won't match any catalog component, so
    /// even when `assignInteriorStrokes` finds a container, the OCR/match step
    /// should reject it.
    func testContainerWithUnreadableInteriorReturnsEmpty() async {
        var drawing = PKDrawing()
        // Outer container: ~400×200 (well above minContainerArea=1800).
        let rect = SketchTemplates.makeRect(x: 100, y: 100, width: 400, height: 200)
        drawing.strokes.append(contentsOf: rect)
        // A short squiggle in the middle that won't resolve to any component name.
        drawing.strokes.append(makeLineStroke(
            from: CGPoint(x: 200, y: 200),
            to: CGPoint(x: 220, y: 210)
        ))

        let catalog: [ComponentDefinition] = []
        let labels = await LabeledBoxDetector.detect(
            drawing: drawing, canvasSize: canvas, catalog: catalog
        )
        XCTAssertTrue(labels.isEmpty, "Empty catalog should never produce a label")
    }

    // MARK: - Identifier uniqueness

    func testLabeledBoxIDsAreUnique() {
        let a = LabeledBoxDetector.LabeledBox(
            bounds: .zero, componentName: "Card", rawText: "card", confidence: 1.0
        )
        let b = LabeledBoxDetector.LabeledBox(
            bounds: .zero, componentName: "Card", rawText: "card", confidence: 1.0
        )
        XCTAssertNotEqual(a.id, b.id, "Each LabeledBox should generate a fresh UUID")
    }

    // MARK: - Geometry tests (skipped — see file header)

    func testInteriorAssignmentPicksSmallestContainer() throws {
        try XCTSkipIf(
            true,
            "assignInteriorStrokes is private; expose it as `internal` if deeper geometry coverage is desired."
        )
    }

    func testTinyContainerIsFilteredOut() throws {
        try XCTSkipIf(
            true,
            "minContainerArea filtering is exercised internally; needs internal-visibility shim to test in isolation."
        )
    }

    // MARK: - Helpers

    private func makeLineStroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let pointCount = 6
        var points: [PKStrokePoint] = []
        for i in 0...pointCount {
            let t = CGFloat(i) / CGFloat(pointCount)
            let location = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
            points.append(PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(t * 0.1),
                size: CGSize(width: 2, height: 2),
                opacity: 1.0,
                force: 0.5,
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }
}
