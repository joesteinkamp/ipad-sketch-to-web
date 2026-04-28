import SwiftUI
import PencilKit

/// A transparent overlay that shows small capsule badges indicating what
/// UI component a freshly drawn shape might represent.
///
/// Two recognition sources feed this overlay:
/// - `StrokeAnalyzer` (immediate, geometric guess from stroke bounds)
/// - `LabeledBoxDetector` (Vision OCR of handwritten text inside boxes)
/// Labeled (handwritten) hints win over geometric ones for any overlapping bounds,
/// since the user typed the answer.
struct DrawingHintOverlay: View {

    let previousDrawing: PKDrawing
    let currentDrawing: PKDrawing
    let canvasSize: CGSize

    @AppStorage("showDrawingHints") var showDrawingHints: Bool = true

    @State private var geometricHints: [StrokeAnalyzer.RecognizedShape] = []
    @State private var labeledHints: [LabeledBoxDetector.LabeledBox] = []
    @State private var labelTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            ForEach(visibleGeometricHints) { hint in
                HintBadge(text: hint.type.rawValue, isLabeled: false)
                    .position(
                        x: hint.bounds.midX,
                        y: hint.bounds.minY - 16
                    )
                    .transition(.opacity.combined(with: .scale))
            }

            ForEach(labeledHints) { hint in
                HintBadge(text: hint.componentName, isLabeled: true)
                    .position(
                        x: hint.bounds.midX,
                        y: hint.bounds.minY - 16
                    )
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: geometricHints.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: labeledHints.map(\.id))
        .onChange(of: currentDrawing) { _, newDrawing in
            guard showDrawingHints else {
                geometricHints = []
                labeledHints = []
                labelTask?.cancel()
                return
            }

            let recognized = StrokeAnalyzer.analyzeNewStrokes(
                previous: previousDrawing,
                current: newDrawing,
                canvasSize: canvasSize
            )
            if !recognized.isEmpty {
                geometricHints = recognized
                scheduleGeometricDismiss()
            }

            scheduleLabelDetection(for: newDrawing)
        }
    }

    /// Hide geometric hints whose bounds are already covered by a labeled hint —
    /// the labeled badge is the more authoritative answer.
    private var visibleGeometricHints: [StrokeAnalyzer.RecognizedShape] {
        guard !labeledHints.isEmpty else { return geometricHints }
        return geometricHints.filter { hint in
            !labeledHints.contains { $0.bounds.intersects(hint.bounds) }
        }
    }

    // MARK: - Auto-dismiss

    private func scheduleGeometricDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: TimingConstants.hintDuration)
            withAnimation {
                geometricHints = []
            }
        }
    }

    // MARK: - Label detection

    /// Runs OCR-based label detection in the background, debounced so it doesn't fire
    /// on every single stroke. Updates `labeledHints` when results arrive.
    private func scheduleLabelDetection(for drawing: PKDrawing) {
        labelTask?.cancel()
        let size = canvasSize
        labelTask = Task { @MainActor in
            // Small debounce so we batch rapid stroke additions before running OCR.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }

            guard let catalog = try? ComponentDefinition.loadCatalog() else { return }
            let detected = await LabeledBoxDetector.detect(
                drawing: drawing,
                canvasSize: size,
                catalog: catalog
            )
            guard !Task.isCancelled else { return }
            withAnimation {
                labeledHints = detected
            }
        }
    }
}

// MARK: - HintBadge

private struct HintBadge: View {
    let text: String
    let isLabeled: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isLabeled {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(isLabeled ? Color.accentColor : Color.secondary)
        .opacity(0.9)
    }
}
