import Foundation
import UIKit
import PencilKit

/// Provides static utility methods for exporting a `PKDrawing` to raster image formats.
enum DrawingExporter {

    /// Renders a PencilKit drawing onto a white background at 2x scale.
    ///
    /// - Parameters:
    ///   - drawing: The `PKDrawing` to render.
    ///   - canvasSize: The logical size of the canvas in points.
    /// - Returns: A `UIImage` containing the drawing composited on a white background.
    static func exportAsImage(_ drawing: PKDrawing, canvasSize: CGSize) -> UIImage {
        let scale: CGFloat = 2.0
        let rect = CGRect(origin: .zero, size: canvasSize)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)

            let drawingImage = drawing.image(from: rect, scale: scale)
            drawingImage.draw(in: rect)
        }
    }

    /// Renders a PencilKit drawing as PNG-encoded data at 2x scale.
    ///
    /// - Parameters:
    ///   - drawing: The `PKDrawing` to render.
    ///   - canvasSize: The logical size of the canvas in points.
    /// - Returns: PNG `Data`, or `nil` if encoding fails.
    static func exportAsPNGData(_ drawing: PKDrawing, canvasSize: CGSize) -> Data? {
        exportAsImage(drawing, canvasSize: canvasSize).pngData()
    }
}
