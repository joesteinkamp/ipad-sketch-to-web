import XCTest
import PencilKit
import UIKit
@testable import SketchToWeb

/// Lightweight checks for `SketchDocument` (the wrapper around `PKDrawing` +
/// `canvasSize`). Image-content invariants live in `DrawingExporterTests`.
@MainActor
final class SketchDocumentTests: XCTestCase {

    func testDefaultsAreEmptyDrawingAndIPadCanvas() {
        let doc = SketchDocument()
        XCTAssertEqual(doc.canvasSize, CGSize(width: 1024, height: 768))
        XCTAssertTrue(doc.drawing.strokes.isEmpty)
    }

    func testCustomCanvasSizeIsHonored() {
        let size = CGSize(width: 2048, height: 1536)
        let doc = SketchDocument(canvasSize: size)
        XCTAssertEqual(doc.canvasSize, size)
    }

    func testExportAsImageMatchesCanvasSize() {
        let doc = SketchDocument(canvasSize: CGSize(width: 300, height: 200))
        let image = doc.exportAsImage(scale: 1.0)
        XCTAssertEqual(image.size.width, 300)
        XCTAssertEqual(image.size.height, 200)
    }

    func testExportAsPNGDataRoundTripsThroughUIImage() throws {
        let doc = SketchDocument(canvasSize: CGSize(width: 100, height: 100))
        let data = try XCTUnwrap(doc.exportAsPNGData(scale: 1.0))
        let restored = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(restored.size.width, 100)
        XCTAssertEqual(restored.size.height, 100)
    }

    func testExportAsPNGDataHasPNGSignature() throws {
        let doc = SketchDocument()
        let data = try XCTUnwrap(doc.exportAsPNGData())
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        XCTAssertEqual([UInt8](data.prefix(4)), signature)
    }

    func testMutatingDrawingAfterInitDoesNotMutateOtherInstances() {
        var docA = SketchDocument()
        let docB = SketchDocument()

        // Append a stroke to A; B should remain empty (value semantics).
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: [], creationDate: Date())
        )
        docA.drawing.strokes.append(stroke)

        XCTAssertEqual(docA.drawing.strokes.count, 1)
        XCTAssertEqual(docB.drawing.strokes.count, 0)
    }
}
