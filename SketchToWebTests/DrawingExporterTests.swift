import XCTest
import PencilKit
import UIKit
@testable import SketchToWeb

/// Verifies `DrawingExporter` renders deterministic, well-formed PNGs at the
/// expected scale and on a white background.
@MainActor
final class DrawingExporterTests: XCTestCase {

    private let canvas = CGSize(width: 200, height: 100)

    // MARK: - Image rendering

    func testExportAsImageReturnsImageMatchingCanvasSizeAt2xScale() {
        let image = DrawingExporter.exportAsImage(PKDrawing(), canvasSize: canvas)
        XCTAssertEqual(image.size, canvas, "UIImage.size is in points; should match canvas")
        XCTAssertEqual(image.scale, 2.0, "Exporter pins scale to 2.0 (Retina)")
        // 2× scale means the underlying CGImage is 2× the point size.
        XCTAssertEqual(image.cgImage?.width, Int(canvas.width * 2))
        XCTAssertEqual(image.cgImage?.height, Int(canvas.height * 2))
    }

    func testExportAsImageRendersWhiteBackgroundForEmptyDrawing() throws {
        let image = DrawingExporter.exportAsImage(PKDrawing(), canvasSize: canvas)
        let center = try centerPixel(of: image)
        XCTAssertEqual(center.r, 255, "Empty drawing should render solid white (R)")
        XCTAssertEqual(center.g, 255, "Empty drawing should render solid white (G)")
        XCTAssertEqual(center.b, 255, "Empty drawing should render solid white (B)")
    }

    // MARK: - PNG encoding

    func testExportAsPNGDataIsNonNil() {
        let data = DrawingExporter.exportAsPNGData(PKDrawing(), canvasSize: canvas)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    func testExportAsPNGDataHasPNGSignature() throws {
        let data = try XCTUnwrap(DrawingExporter.exportAsPNGData(PKDrawing(), canvasSize: canvas))
        XCTAssertGreaterThanOrEqual(data.count, 8)
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual([UInt8](data.prefix(8)), signature)
    }

    func testExportAsPNGDataRoundTripsThroughUIImage() throws {
        let data = try XCTUnwrap(DrawingExporter.exportAsPNGData(PKDrawing(), canvasSize: canvas))
        let restored = try XCTUnwrap(UIImage(data: data))
        // PNG carries pixel dimensions, not point size + scale, so the round-tripped
        // UIImage will have scale 1.0 with size = pixel dimensions of the source.
        XCTAssertEqual(restored.size.width, canvas.width * 2)
        XCTAssertEqual(restored.size.height, canvas.height * 2)
    }

    // MARK: - Helpers

    private struct RGBA: Equatable {
        let r, g, b, a: UInt8
    }

    /// Reads the pixel at the geometric center of a `UIImage`.
    private func centerPixel(of image: UIImage) throws -> RGBA {
        let cgImage = try XCTUnwrap(image.cgImage, "UIImage missing CGImage")
        let width = cgImage.width
        let height = cgImage.height

        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: &pixel,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Translate the CGImage so its center maps to (0,0) of our 1×1 context.
        context.translateBy(x: CGFloat(-width / 2), y: CGFloat(-height / 2))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return RGBA(r: pixel[0], g: pixel[1], b: pixel[2], a: pixel[3])
    }
}
