import Foundation
import UIKit
import PencilKit

/// A lightweight wrapper around a PencilKit drawing and its canvas dimensions.
/// Provides convenience methods for rendering the drawing as an image.
struct SketchDocument {
    var drawing: PKDrawing
    var canvasSize: CGSize

    init(drawing: PKDrawing = PKDrawing(), canvasSize: CGSize = CGSize(width: 1024, height: 768)) {
        self.drawing = drawing
        self.canvasSize = canvasSize
    }

    /// Renders the drawing on a white background at the specified scale.
    ///
    /// - Parameter scale: The rendering scale factor. Defaults to 2.0 (Retina).
    /// - Returns: A `UIImage` of the drawing composited onto a white background.
    func exportAsImage(scale: CGFloat = 2.0) -> UIImage {
        let rect = CGRect(origin: .zero, size: canvasSize)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(rect)

            // Render the PencilKit drawing
            let drawingImage = drawing.image(from: rect, scale: scale)
            drawingImage.draw(in: rect)
        }
    }

    /// Renders the drawing as PNG data suitable for upload or on-device processing.
    ///
    /// - Parameter scale: The rendering scale factor. Defaults to 2.0 (Retina).
    /// - Returns: PNG-encoded `Data`, or `nil` if encoding fails.
    func exportAsPNGData(scale: CGFloat = 2.0) -> Data? {
        exportAsImage(scale: scale).pngData()
    }
}
