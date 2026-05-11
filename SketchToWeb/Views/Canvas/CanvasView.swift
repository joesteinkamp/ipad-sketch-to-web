import SwiftUI
import PencilKit

/// The main drawing screen that hosts the PencilKit canvas and a floating toolbar.
///
/// `CanvasView` reads the project's persisted drawing data on appear, auto-saves
/// changes back to the project model, and exposes the canvas dimensions to
/// `AppState` so that export/conversion can use the correct size.
struct CanvasView: View {

    /// The project whose drawing is being edited. Pass `nil` for a scratch canvas.
    @Binding var project: Project?

    @State private var drawing = PKDrawing()
    @State private var previousDrawing = PKDrawing()
    @State private var isToolPickerVisible: Bool = true
    @State private var showTextToSketch = false
    @State private var showTemplatePicker = false
    @State private var activeTool: DrawingTool = .pen
    @State private var penThickness: PenThickness = .medium
    @State private var drawingCorruptionError: String?

    @StateObject private var canvasController = CanvasController()
    @EnvironmentObject private var appState: AppState

    /// Debounce timer used to coalesce rapid drawing changes before persisting.
    @State private var saveTask: Task<Void, Never>?

    /// Task that triggers auto-conversion after a drawing pause.
    @State private var autoConvertTask: Task<Void, Never>?

    /// Set while we're translating the drawing to keep it centered after a
    /// viewport resize, so the resulting `drawing` change doesn't schedule
    /// an auto-conversion.
    @State private var isRecenteringDrawing = false

    /// User preference: automatically convert after a 3-second drawing pause.
    @AppStorage("autoConvertEnabled") private var autoConvertEnabled: Bool = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full-bleed PencilKit canvas
                PencilCanvasView(
                    drawing: $drawing,
                    isToolPickerVisible: $isToolPickerVisible,
                    activeTool: activeTool,
                    penWidth: penThickness.rawValue,
                    canvasController: canvasController
                )
                .ignoresSafeArea()

                // Drawing recognition hint badges
                DrawingHintOverlay(
                    previousDrawing: previousDrawing,
                    currentDrawing: drawing,
                    canvasSize: geometry.size
                )

                // Floating toolbar pinned to the bottom
                VStack {
                    Spacer()
                    CanvasToolbar(
                        canvasController: canvasController,
                        activeTool: $activeTool,
                        penThickness: $penThickness,
                        onClear: clearDrawing
                    )
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                loadDrawing()
                appState.canvasSize = geometry.size
                appState.currentDrawing = drawing
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                appState.canvasSize = newSize
                recenterDrawing(from: oldSize, to: newSize)
            }
        }
        .onChange(of: drawing) { oldDrawing, newDrawing in
            previousDrawing = oldDrawing
            debouncedSave(newDrawing)
            if !isRecenteringDrawing {
                scheduleAutoConvert(for: newDrawing)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showTextToSketch = true
                } label: {
                    Label("Text to Sketch", systemImage: "lightbulb")
                }
                .accessibilityLabel("Text to Sketch")

                Button {
                    showTemplatePicker = true
                } label: {
                    Label("Templates", systemImage: "rectangle.grid.2x2")
                }
                .accessibilityLabel("Templates")
            }
        }
        .sheet(isPresented: $showTextToSketch) {
            TextToSketchSheet(
                onDrawingGenerated: { newDrawing in
                    mergeDrawing(newDrawing)
                },
                canvasSize: appState.canvasSize
            )
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerSheet(
                onTemplateSelected: { templateDrawing in
                    drawing = templateDrawing
                    saveImmediately()
                },
                canvasSize: appState.canvasSize
            )
        }
        .alert("Drawing Data Corrupted", isPresented: Binding(
            get: { drawingCorruptionError != nil },
            set: { if !$0 { drawingCorruptionError = nil } }
        )) {
            Button("OK") { drawingCorruptionError = nil }
        } message: {
            if let error = drawingCorruptionError {
                Text("The saved drawing could not be loaded and was reset. Error: \(error)")
            }
        }
    }

    // MARK: - Actions

    /// Replaces the drawing with an empty canvas.
    private func clearDrawing() {
        drawing = PKDrawing()
        saveImmediately()
    }

    /// Merges new strokes into the existing drawing (appends without replacing).
    private func mergeDrawing(_ newDrawing: PKDrawing) {
        var merged = drawing
        for stroke in newDrawing.strokes {
            merged.strokes.append(stroke)
        }
        drawing = merged
        saveImmediately()
    }

    // MARK: - Re-centering

    /// Translates the drawing so its bounding box stays centered when the
    /// canvas viewport resizes — for example when the user flips between
    /// Split and Sketch layout modes. PencilKit strokes live in absolute
    /// canvas coordinates, so without this the drawing remains anchored to
    /// the top-left and appears to drift to one side as the canvas grows.
    private func recenterDrawing(from oldSize: CGSize, to newSize: CGSize) {
        guard oldSize.width > 0, oldSize.height > 0 else { return }
        guard oldSize != newSize else { return }
        guard !drawing.strokes.isEmpty else { return }

        let bounds = drawing.bounds
        let deltaX = newSize.width / 2 - bounds.midX
        let deltaY = newSize.height / 2 - bounds.midY
        guard abs(deltaX) > 0.5 || abs(deltaY) > 0.5 else { return }

        isRecenteringDrawing = true
        drawing = drawing.transformed(using: CGAffineTransform(translationX: deltaX, y: deltaY))
        saveImmediately()
        DispatchQueue.main.async { isRecenteringDrawing = false }
    }

    // MARK: - Persistence

    /// Loads the drawing from the project's persisted data, if available.
    private func loadDrawing() {
        guard let data = project?.drawingData else { return }
        do {
            drawing = try PKDrawing(data: data)
        } catch {
            drawingCorruptionError = error.localizedDescription
            drawing = PKDrawing()
        }
    }

    /// Debounces save calls so we don't write to the model on every single stroke.
    private func debouncedSave(_ newDrawing: PKDrawing) {
        appState.currentDrawing = newDrawing
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: TimingConstants.drawingDebounce)
            guard !Task.isCancelled else { return }
            project?.drawingData = newDrawing.dataRepresentation()
        }
    }

    /// Writes the current drawing to the project immediately (e.g. after clear).
    private func saveImmediately() {
        saveTask?.cancel()
        project?.drawingData = drawing.dataRepresentation()
    }

    // MARK: - Auto-Convert

    /// Schedules an automatic conversion after a 3-second drawing pause.
    /// Cancels any previously scheduled auto-convert task.
    private func scheduleAutoConvert(for newDrawing: PKDrawing) {
        autoConvertTask?.cancel()

        guard autoConvertEnabled, !newDrawing.strokes.isEmpty else { return }

        autoConvertTask = Task { @MainActor in
            try? await Task.sleep(for: TimingConstants.autoConvertDelay)
            guard !Task.isCancelled else { return }
            appState.convertDrawing()
        }
    }
}
