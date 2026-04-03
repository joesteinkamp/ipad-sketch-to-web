import Foundation
import PencilKit

/// Lightweight shape detector that inspects PencilKit stroke bounding boxes
/// to guess which UI component the user might be drawing.
struct StrokeAnalyzer {

    // MARK: - Types

    enum ShapeType: String, CaseIterable, Sendable {
        case button = "Button"
        case input = "Input"
        case card = "Card"
        case checkbox = "Checkbox"
        case radio = "Radio"
        case separator = "Separator"
        case navigation = "Navigation"
        case unknown = "Unknown"
    }

    struct RecognizedShape: Identifiable, Sendable {
        let id = UUID()
        let type: ShapeType
        let bounds: CGRect
        let confidence: Double
    }

    // MARK: - Public API

    /// Compares the previous and current drawings, finds newly added strokes,
    /// and returns recognized shapes for those strokes.
    static func analyzeNewStrokes(
        previous: PKDrawing,
        current: PKDrawing,
        canvasSize: CGSize = CGSize(width: 1024, height: 768)
    ) -> [RecognizedShape] {
        let previousCount = previous.strokes.count
        let currentCount = current.strokes.count

        guard currentCount > previousCount else { return [] }

        let newStrokes = Array(current.strokes[previousCount...])
        return newStrokes.compactMap { classify(stroke: $0, canvasSize: canvasSize) }
    }

    // MARK: - Classification

    private static func classify(stroke: PKStroke, canvasSize: CGSize) -> RecognizedShape? {
        let bounds = stroke.renderBounds

        // Filter out tiny accidental marks
        guard bounds.width > 5 || bounds.height > 5 else { return nil }

        let width = bounds.width
        let height = bounds.height
        let aspectRatio = width / max(height, 1)

        // Very small square → Checkbox
        if width < 30 && height < 30 && aspectRatio > 0.6 && aspectRatio < 1.6 {
            return RecognizedShape(type: .checkbox, bounds: bounds, confidence: 0.7)
        }

        // Small circle → Radio (small, roughly square bounding box)
        if max(width, height) < 30 && aspectRatio > 0.7 && aspectRatio < 1.4 {
            return RecognizedShape(type: .radio, bounds: bounds, confidence: 0.6)
        }

        // Horizontal line spanning > 60% of canvas width → Separator
        if height < 15 && width > canvasSize.width * 0.6 {
            return RecognizedShape(type: .separator, bounds: bounds, confidence: 0.8)
        }

        // Horizontal bar at top of canvas → Navigation
        if bounds.minY < canvasSize.height * 0.1 && width > canvasSize.width * 0.5 && height < 80 {
            return RecognizedShape(type: .navigation, bounds: bounds, confidence: 0.75)
        }

        // Large rectangle → Card
        if width > 300 && height > 200 {
            return RecognizedShape(type: .card, bounds: bounds, confidence: 0.7)
        }

        // Input field: aspect ratio 5:1 to 8:1, width > 200
        if aspectRatio >= 5 && aspectRatio <= 8 && width > 200 {
            return RecognizedShape(type: .input, bounds: bounds, confidence: 0.75)
        }

        // Button: small rectangle with aspect ratio 3:1 to 5:1, width < 200
        if aspectRatio >= 3 && aspectRatio < 5 && width < 200 {
            return RecognizedShape(type: .button, bounds: bounds, confidence: 0.7)
        }

        return nil
    }
}
