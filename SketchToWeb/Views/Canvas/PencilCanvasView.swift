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
    var activeTool: DrawingTool = .pen
    var penWidth: CGFloat = PenThickness.medium.rawValue
    var canvasController: CanvasController?

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, canvasController: canvasController)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        // Accept both Apple Pencil and finger input. `.pencilOnly` would reject
        // every touch on the simulator (no pencil) and on iPads where users
        // prefer finger sketching.
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator
        canvasView.drawing = drawing

        // Set initial tool
        canvasView.tool = toolForCurrentState()

        // Configure the tool picker and keep a strong reference in the coordinator.
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        context.coordinator.toolPicker = toolPicker
        context.coordinator.canvasView = canvasView

        // Attach the controller for direct undo/redo calls.
        canvasController?.attach(canvasView)

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

        // Update tool when activeTool or penWidth changes.
        canvasView.tool = toolForCurrentState()

        // Show or hide the tool picker based on the binding.
        if let toolPicker = context.coordinator.toolPicker {
            toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvasView)
            if isToolPickerVisible {
                canvasView.becomeFirstResponder()
            }
        }
    }

    // MARK: - Tool Construction

    private func toolForCurrentState() -> PKTool {
        switch activeTool {
        case .pen:
            return PKInkingTool(.pen, color: .black, width: penWidth)
        case .eraser:
            return PKEraserTool(.bitmap)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>

        /// Strong reference keeps the tool picker alive for the lifetime of the canvas.
        var toolPicker: PKToolPicker?

        /// Reference to the canvas for undo manager access.
        var canvasView: PKCanvasView?

        /// Controller for direct undo/redo calls from the toolbar.
        private weak var canvasController: CanvasController?

        init(drawing: Binding<PKDrawing>, canvasController: CanvasController?) {
            self.drawing = drawing
            self.canvasController = canvasController
            super.init()
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Push changes back to the SwiftUI binding.
            DispatchQueue.main.async { [weak self] in
                self?.drawing.wrappedValue = canvasView.drawing
                self?.canvasController?.updateUndoState()
            }
        }
    }
}
