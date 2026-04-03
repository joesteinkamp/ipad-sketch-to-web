import SwiftUI

/// A floating capsule toolbar overlaid at the bottom of the canvas.
///
/// Provides quick actions: tool selection (pen/eraser), thickness, undo, redo,
/// clear, and the primary "Convert to Code" button.
struct CanvasToolbar: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject var canvasController: CanvasController

    @Binding var activeTool: DrawingTool
    @Binding var penThickness: PenThickness

    /// Called when the user taps "Clear".
    var onClear: () -> Void

    @State private var showThicknessPicker = false

    var body: some View {
        HStack(spacing: 16) {
            // Pen tool
            Button {
                activeTool = .pen
            } label: {
                Label("Pen", systemImage: "pencil.tip")
                    .labelStyle(.iconOnly)
            }
            .foregroundStyle(activeTool == .pen ? .blue : .primary)
            .accessibilityLabel("Pen Tool")

            // Eraser tool
            Button {
                activeTool = activeTool == .eraser ? .pen : .eraser
            } label: {
                Label("Eraser", systemImage: "eraser")
                    .labelStyle(.iconOnly)
            }
            .foregroundStyle(activeTool == .eraser ? .blue : .primary)
            .accessibilityLabel("Eraser Tool")

            // Line thickness
            Button {
                showThicknessPicker.toggle()
            } label: {
                Label("Thickness", systemImage: "lineweight")
                    .labelStyle(.iconOnly)
            }
            .popover(isPresented: $showThicknessPicker) {
                VStack(spacing: 12) {
                    Text("Line Thickness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Thickness", selection: $penThickness) {
                        ForEach(PenThickness.allCases) { thickness in
                            Text(thickness.label).tag(thickness)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .frame(width: 220)
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel("Line Thickness")

            Divider()
                .frame(height: 24)

            // Undo
            Button {
                canvasController.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .disabled(!canvasController.canUndo)
            .accessibilityLabel("Undo")

            // Redo
            Button {
                canvasController.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .labelStyle(.iconOnly)
            }
            .disabled(!canvasController.canRedo)
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
