import Foundation
import Combine
import PencilKit

/// A lightweight controller that bridges SwiftUI actions to the PKCanvasView's Coordinator.
/// Replaces the NotificationCenter-based undo/redo pattern with direct method calls.
@MainActor
final class CanvasController: ObservableObject {
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    private weak var canvasView: PKCanvasView?

    func attach(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
        // Defer the @Published update so it doesn't fire during the SwiftUI
        // view update that triggered `makeUIView`.
        Task { @MainActor in
            updateUndoState()
        }
    }

    func undo() {
        canvasView?.undoManager?.undo()
        updateUndoState()
    }

    func redo() {
        canvasView?.undoManager?.redo()
        updateUndoState()
    }

    func updateUndoState() {
        canUndo = canvasView?.undoManager?.canUndo ?? false
        canRedo = canvasView?.undoManager?.canRedo ?? false
    }
}
