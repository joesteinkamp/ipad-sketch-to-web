import XCTest
import PencilKit
@testable import SketchToWeb

/// Verifies the five built-in wireframe templates produce well-formed `PKDrawing`s
/// that fit inside the requested canvas and have the expected stroke topology.
@MainActor
final class SketchTemplatesTests: XCTestCase {

    private let canvas = CGSize(width: 1024, height: 768)

    // MARK: - Catalog

    func testCatalogContainsFiveTemplates() {
        XCTAssertEqual(SketchTemplates.all.count, 5)
        let names = SketchTemplates.all.map(\.name)
        XCTAssertEqual(Set(names).count, 5, "Template names should be unique")
    }

    func testEveryTemplateHasIcon() {
        for template in SketchTemplates.all {
            XCTAssertFalse(
                template.iconName.isEmpty,
                "Template \(template.name) is missing an SF Symbol icon"
            )
        }
    }

    // MARK: - Generators produce non-empty drawings

    func testEveryTemplateGeneratesAtLeastOneStroke() {
        for template in SketchTemplates.all {
            let drawing = template.generator(canvas)
            XCTAssertFalse(
                drawing.strokes.isEmpty,
                "Template \(template.name) produced an empty drawing"
            )
        }
    }

    func testEveryTemplateFitsInsideCanvas() {
        for template in SketchTemplates.all {
            let drawing = template.generator(canvas)
            let bounds = drawing.bounds
            XCTAssertGreaterThanOrEqual(
                bounds.minX, -1,
                "Template \(template.name) drew left of canvas (minX=\(bounds.minX))"
            )
            XCTAssertGreaterThanOrEqual(
                bounds.minY, -1,
                "Template \(template.name) drew above canvas (minY=\(bounds.minY))"
            )
            XCTAssertLessThanOrEqual(
                bounds.maxX, canvas.width + 1,
                "Template \(template.name) drew right of canvas (maxX=\(bounds.maxX))"
            )
            XCTAssertLessThanOrEqual(
                bounds.maxY, canvas.height + 1,
                "Template \(template.name) drew below canvas (maxY=\(bounds.maxY))"
            )
        }
    }

    // MARK: - Helper geometry

    func testMakeRectProducesFourLineStrokes() {
        let strokes = SketchTemplates.makeRect(x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(strokes.count, 4, "Rectangle should be 4 sides as separate strokes")
        // Each line stroke should run between two of the rectangle's corners.
        let combined = strokes.reduce(into: CGRect.null) { acc, stroke in
            acc = acc.union(stroke.renderBounds)
        }
        XCTAssertEqual(combined.minX, 10, accuracy: 2)
        XCTAssertEqual(combined.minY, 20, accuracy: 2)
        XCTAssertEqual(combined.width, 100, accuracy: 2)
        XCTAssertEqual(combined.height, 50, accuracy: 2)
    }

    func testMakeLineProducesSingleStroke() {
        let strokes = SketchTemplates.makeLine(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0)
        )
        XCTAssertEqual(strokes.count, 1)
    }

    func testMakeTextPlaceholderProducesSingleStroke() {
        let strokes = SketchTemplates.makeTextPlaceholder(x: 0, y: 0, width: 50)
        XCTAssertEqual(strokes.count, 1)
    }

    func testMakeCircleProducesSingleStroke() {
        let strokes = SketchTemplates.makeCircle(cx: 100, cy: 100, radius: 30)
        XCTAssertEqual(strokes.count, 1)
        let bounds = strokes[0].renderBounds
        // Approximation of a circle should be roughly square in bounds.
        XCTAssertEqual(bounds.width, 60, accuracy: 6)
        XCTAssertEqual(bounds.height, 60, accuracy: 6)
    }

    // MARK: - Generators are deterministic in stroke count

    func testLoginFormStrokeCountIsStable() {
        let drawing = SketchTemplates.loginForm(canvasSize: canvas)
        // Card (4) + title (1) + email label (1) + email field (4) +
        // password label (1) + password field (4) + button (5: 4 outline + 1 text) +
        // forgot link (1) = 21 strokes. A change here probably means the template
        // visually changed; update the constant if so.
        XCTAssertEqual(drawing.strokes.count, 21)
    }

    func testTemplatesAreIndependentRuns() {
        // Calling a generator twice returns equivalent stroke counts; templates
        // should have no global state.
        let a = SketchTemplates.dashboard(canvasSize: canvas)
        let b = SketchTemplates.dashboard(canvasSize: canvas)
        XCTAssertEqual(a.strokes.count, b.strokes.count)
    }

    // MARK: - Canvas independence

    /// Templates should adapt to canvas size — running them at different sizes
    /// should still produce non-empty, in-bounds output (no fixed coordinates
    /// outside the canvas).
    func testTemplatesAdaptToSmallCanvas() {
        let small = CGSize(width: 800, height: 600)
        for template in SketchTemplates.all {
            let drawing = template.generator(small)
            XCTAssertFalse(drawing.strokes.isEmpty, "\(template.name) empty on 800×600")
            XCTAssertLessThanOrEqual(drawing.bounds.maxX, small.width + 1, "\(template.name)")
            XCTAssertLessThanOrEqual(drawing.bounds.maxY, small.height + 1, "\(template.name)")
        }
    }
}
