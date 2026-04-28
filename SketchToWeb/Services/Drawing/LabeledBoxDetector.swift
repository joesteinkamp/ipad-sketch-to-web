import Foundation
import PencilKit
import UIKit

/// Detects rectangles drawn by the user that contain handwritten component labels inside them
/// (e.g. a box with the word "card" written in it).
///
/// Pipeline:
/// 1. Pick container strokes — strokes whose bounds enclose at least one other stroke.
/// 2. For each container, render only the *interior* strokes onto a white background,
///    cropped to the container's bounds.
/// 3. Run `HandwritingRecognizer` against that cropped image.
/// 4. Match the OCR text against the component catalog via `ComponentLabelMatcher`.
enum LabeledBoxDetector {

    /// A box the user explicitly labeled by writing a component name inside it.
    struct LabeledBox: Sendable, Identifiable {
        let id = UUID()
        let bounds: CGRect
        let componentName: String
        let rawText: String
        let confidence: Double
    }

    /// Minimum box area (in points squared) considered for label detection.
    /// Skips tiny scribbles where text recognition would be unreliable.
    private static let minContainerArea: CGFloat = 60 * 30

    /// How many points of slack to allow when testing whether one stroke's bounds
    /// fall inside another's. Hand drawing isn't pixel-perfect.
    private static let containmentTolerance: CGFloat = 6

    /// Detects all labeled boxes on the given drawing. PencilKit rendering is performed
    /// on the main actor; the OCR work itself hops to a background queue inside
    /// `HandwritingRecognizer`, so `await`-ing this from the main actor does not block UI.
    ///
    /// - Parameters:
    ///   - drawing: The PencilKit drawing.
    ///   - canvasSize: The size of the canvas the drawing was created on. Used to scale rendering.
    ///   - catalog: The component catalog driving matcher vocabulary.
    /// - Returns: All boxes whose interior text matched a known component, deduped.
    @MainActor
    static func detect(
        drawing: PKDrawing,
        canvasSize: CGSize,
        catalog: [ComponentDefinition]
    ) async -> [LabeledBox] {
        let strokes = drawing.strokes
        guard strokes.count >= 2 else { return [] }

        let assignments = assignInteriorStrokes(strokes: strokes)
        guard !assignments.isEmpty else { return [] }

        let customWords = Array(Set(
            catalog.map(\.name) + catalog.map { $0.name.lowercased() }
        ))

        var labels: [LabeledBox] = []
        for (containerIndex, interiorIndices) in assignments {
            let container = strokes[containerIndex]
            let interiorStrokes = interiorIndices.map { strokes[$0] }
            guard let cgImage = renderInteriorStrokes(
                interiorStrokes,
                cropTo: container.renderBounds,
                canvasSize: canvasSize
            ) else {
                continue
            }

            do {
                let candidates = try await HandwritingRecognizer.recognize(
                    in: cgImage,
                    customWords: customWords
                )
                if let match = ComponentLabelMatcher.bestMatch(among: candidates, catalog: catalog) {
                    labels.append(LabeledBox(
                        bounds: container.renderBounds,
                        componentName: match.componentName,
                        rawText: match.rawText,
                        confidence: match.confidence
                    ))
                }
            } catch {
                // OCR is best-effort — a recognizer failure for one box shouldn't
                // abort the whole detection pass.
                continue
            }
        }
        return labels
    }

    // MARK: - Container assignment

    /// For each container-eligible stroke, returns the indices of strokes that fall inside it.
    /// Each interior stroke is assigned to the *smallest* enclosing container so that nested
    /// rectangles don't double-count.
    private static func assignInteriorStrokes(strokes: [PKStroke]) -> [(container: Int, interior: [Int])] {
        // Pre-compute bounds and area; sort container candidates by area ascending.
        let entries = strokes.enumerated().map { (index: $0.offset, bounds: $0.element.renderBounds) }
        let containerCandidates = entries
            .filter { $0.bounds.width * $0.bounds.height >= minContainerArea }
            .sorted { ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height) }

        var claimedByContainer: [Int: [Int]] = [:]
        var claimedStrokes = Set<Int>()

        for candidate in containerCandidates {
            let expanded = candidate.bounds.insetBy(dx: -containmentTolerance, dy: -containmentTolerance)
            var interior: [Int] = []
            for entry in entries where entry.index != candidate.index && !claimedStrokes.contains(entry.index) {
                if expanded.contains(entry.bounds) {
                    interior.append(entry.index)
                }
            }
            guard !interior.isEmpty else { continue }
            claimedByContainer[candidate.index] = interior
            interior.forEach { claimedStrokes.insert($0) }
        }

        return claimedByContainer.map { (container: $0.key, interior: $0.value) }
    }

    // MARK: - Rendering

    /// Renders the given strokes onto a white background, cropped to the supplied rect.
    /// The returned image is sized to the container's bounds (1× scale for OCR speed).
    @MainActor
    private static func renderInteriorStrokes(
        _ strokes: [PKStroke],
        cropTo rect: CGRect,
        canvasSize: CGSize
    ) -> CGImage? {
        guard !strokes.isEmpty, rect.width > 0, rect.height > 0 else { return nil }

        var subDrawing = PKDrawing()
        subDrawing.strokes.append(contentsOf: strokes)

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            // Translate so that `rect`'s origin maps to (0, 0) in the output image.
            context.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            let drawingImage = subDrawing.image(
                from: CGRect(origin: .zero, size: canvasSize),
                scale: 1.0
            )
            drawingImage.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
        return image.cgImage
    }
}
