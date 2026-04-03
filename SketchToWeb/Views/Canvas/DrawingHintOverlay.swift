import SwiftUI
import PencilKit

/// A transparent overlay that shows small capsule badges indicating what
/// UI component a freshly drawn shape might represent.
struct DrawingHintOverlay: View {

    let previousDrawing: PKDrawing
    let currentDrawing: PKDrawing
    let canvasSize: CGSize

    @AppStorage("showDrawingHints") var showDrawingHints: Bool = true

    @State private var hints: [StrokeAnalyzer.RecognizedShape] = []

    var body: some View {
        ZStack {
            ForEach(hints) { hint in
                HintBadge(shape: hint)
                    .position(
                        x: hint.bounds.midX,
                        y: hint.bounds.minY - 16
                    )
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: hints.map(\.id))
        .onChange(of: currentDrawing) { _, newDrawing in
            guard showDrawingHints else {
                hints = []
                return
            }
            let recognized = StrokeAnalyzer.analyzeNewStrokes(
                previous: previousDrawing,
                current: newDrawing,
                canvasSize: canvasSize
            )
            guard !recognized.isEmpty else { return }
            hints = recognized
            scheduleDismiss()
        }
    }

    // MARK: - Auto-dismiss

    private func scheduleDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: TimingConstants.hintDuration)
            withAnimation {
                hints = []
            }
        }
    }
}

// MARK: - HintBadge

private struct HintBadge: View {
    let shape: StrokeAnalyzer.RecognizedShape

    var body: some View {
        Text(shape.type.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
            .opacity(0.85)
    }
}
