import SwiftUI

/// A floating capsule toolbar overlaid at the bottom of the canvas.
///
/// Provides quick actions: undo, redo, clear, and the primary "Convert to Code"
/// button that triggers AI conversion through `AppState`.
struct CanvasToolbar: View {

    @EnvironmentObject private var appState: AppState

    /// Called when the user taps "Clear".
    var onClear: () -> Void

    /// Called when the user taps "Undo".
    var onUndo: () -> Void

    /// Called when the user taps "Redo".
    var onRedo: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            // Undo
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Undo")

            // Redo
            Button(action: onRedo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Redo")

            Divider()
                .frame(height: 24)

            // Clear
            Button(role: .destructive, action: onClear) {
                Label("Clear", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Clear Canvas")

            Divider()
                .frame(height: 24)

            // Convert to Code
            Button {
                appState.convertDrawing()
            } label: {
                HStack(spacing: 6) {
                    if appState.isConverting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text("Convert")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isConverting)
            .accessibilityLabel("Convert to Code")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
