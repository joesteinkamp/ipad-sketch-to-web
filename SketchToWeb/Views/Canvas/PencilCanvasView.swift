import SwiftUI
import PencilKit

/// A UIViewRepresentable wrapper around PKCanvasView for Apple Pencil drawing.
///
/// This view manages the full lifecycle of both the canvas and the tool picker,
/// keeping the tool picker instance alive as a Coordinator property so it does
/// not get deallocated while the canvas is visible.
struct PencilCanvasView: UIViewRepresentable {

    @Binding var drawing: PKDrawing
    @Binding var isToolPickerVisible: Bool

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator
        canvasView.drawing = drawing

        // Default tool: black pen, width 3
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)

        // Configure the tool picker and keep a strong reference in the coordinator.
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        context.coordinator.toolPicker = toolPicker
        context.coordinator.canvasView = canvasView

        // The canvas must be first responder for the tool picker to appear.
        DispatchQueue.main.async {
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        // Sync drawing from SwiftUI state into the canvas when the model changes
        // externally (e.g. undo, clear). Avoid feedback loops by only updating
        // when the data actually differs.
        if canvasView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvasView.drawing = drawing
        }

        // Show or hide the tool picker based on the binding.
        if let toolPicker = context.coordinator.toolPicker {
            toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvasView)
            if isToolPickerVisible {
                canvasView.becomeFirstResponder()
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>

        /// Strong reference keeps the tool picker alive for the lifetime of the canvas.
        var toolPicker: PKToolPicker?

        /// Weak-ish reference to the canvas so we can interact with undo manager, etc.
        var canvasView: PKCanvasView?

        private var undoObserver: Any?
        private var redoObserver: Any?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
            super.init()
            subscribeToUndoRedo()
        }

        deinit {
            if let undoObserver { NotificationCenter.default.removeObserver(undoObserver) }
            if let redoObserver { NotificationCenter.default.removeObserver(redoObserver) }
        }

        private func subscribeToUndoRedo() {
            undoObserver = NotificationCenter.default.addObserver(
                forName: .canvasUndoRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.canvasView?.undoManager?.undo()
            }

            redoObserver = NotificationCenter.default.addObserver(
                forName: .canvasRedoRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.canvasView?.undoManager?.redo()
            }
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Push changes back to the SwiftUI binding.
            DispatchQueue.main.async { [weak self] in
                self?.drawing.wrappedValue = canvasView.drawing
            }
        }
    }
}
