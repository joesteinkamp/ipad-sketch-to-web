import Foundation
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
        updateUndoState()
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
