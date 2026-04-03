import Foundation
import PencilKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isConverting = false
    @Published var isRefining = false
    @Published var conversionError: String?
    @Published var generatedResult: GeneratedCode?
    @Published var streamingText: String?

    /// History of generated code versions for back/forward navigation.
    @Published var generationHistory: [GeneratedCode] = []

    /// Index into `generationHistory` pointing to the currently displayed version.
    @Published var generationHistoryIndex: Int = -1

    /// Current canvas size, updated by CanvasView via GeometryReader.
    var canvasSize: CGSize = CGSize(width: 1024, height: 768)

    /// The current drawing, kept in sync by CanvasView.
    var currentDrawing = PKDrawing()

    /// The current project, set by the view layer so that generation records can be saved.
    var currentProject: Project?

    /// Closure invoked after a successful conversion with the new Generation.
    /// The view layer sets this to insert the record into the model context.
    var onGenerationCreated: ((Generation) -> Void)?

    /// Whether the user can navigate back in generation history.
    var canGoBack: Bool {
        generationHistoryIndex > 0
    }

    /// Whether the user can navigate forward in generation history.
    var canGoForward: Bool {
        generationHistoryIndex < generationHistory.count - 1
    }

    /// Converts the current drawing using the AI pipeline.
    /// Called from the toolbar's Convert button (no arguments needed).
    func convertDrawing() {
        guard !isConverting else { return }

        isConverting = true
        conversionError = nil
        streamingText = nil

        Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
                    throw AIConversionPipeline.PipelineError.apiKeyMissing
                }
                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let pipeline = AIConversionPipeline(apiKey: apiKey, model: model)

                for try await state in pipeline.convertStreaming(drawing: currentDrawing, canvasSize: canvasSize) {
                    switch state {
                    case .generating(let partialText):
                        self.streamingText = partialText
                    case .completed(let result):
                        self.pushGeneratedResult(result)
                        self.streamingText = nil
                    }
                }
            } catch {
                self.conversionError = error.localizedDescription
                self.streamingText = nil
            }
            self.isConverting = false
        }
    }

    /// Refines the current generated result using annotation feedback.
    ///
    /// - Parameters:
    ///   - annotationImage: PNG data of the composite screenshot with red annotations.
    ///   - canvasSize: The size of the preview area.
    func refineResult(annotationImage: Data, canvasSize: CGSize) {
        guard !isRefining, let currentCode = generatedResult else { return }

        isRefining = true
        conversionError = nil

        Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
                    throw RefinementPipeline.RefinementError.apiKeyMissing
                }
                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let pipeline = RefinementPipeline(apiKey: apiKey, model: model)
                let result = try await pipeline.refine(
                    currentCode: currentCode,
                    annotationImage: annotationImage,
                    canvasSize: canvasSize
                )
                self.pushGeneratedResult(result)
            } catch {
                self.conversionError = error.localizedDescription
            }
            self.isRefining = false
        }
    }

    /// Navigates to the previous version in generation history.
    func goBack() {
        guard canGoBack else { return }
        generationHistoryIndex -= 1
        generatedResult = generationHistory[generationHistoryIndex]
    }

    /// Navigates to the next version in generation history.
    func goForward() {
        guard canGoForward else { return }
        generationHistoryIndex += 1
        generatedResult = generationHistory[generationHistoryIndex]
    }

    // MARK: - Private Helpers

    /// Pushes a new result onto the history stack and updates the current result.
    private func pushGeneratedResult(_ result: GeneratedCode) {
        // If we navigated back and then generate a new result, discard forward history.
        if generationHistoryIndex < generationHistory.count - 1 {
            generationHistory = Array(generationHistory.prefix(generationHistoryIndex + 1))
        }
        generationHistory.append(result)
        generationHistoryIndex = generationHistory.count - 1
        generatedResult = result

        // Persist the generation to the project's history.
        saveGeneration(result)
    }

    /// Creates a `Generation` record and hands it to the view layer for persistence.
    private func saveGeneration(_ result: GeneratedCode) {
        guard let project = currentProject else { return }
        let generation = Generation(
            htmlPreview: result.htmlPreview,
            reactCode: result.reactCode,
            drawingSnapshot: currentDrawing.dataRepresentation(),
            project: project
        )
        onGenerationCreated?(generation)
    }
}
