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
    /// Not `@Published` — it's only read inside conversion methods and never
    /// observed reactively. Publishing it during a layout pass causes
    /// "Publishing changes from within view updates" warnings.
    var canvasSize: CGSize = CGSize(width: 1024, height: 768)

    /// The current drawing, kept in sync by CanvasView. Not `@Published` for
    /// the same reason as `canvasSize`.
    var currentDrawing = PKDrawing()

    /// The current project, set by the view layer so that generation records can be saved.
    @Published var currentProject: Project?

    /// Snapshot of the active design system. Pushed in by `ContentView` via a
    /// `@Query` observer so the pipelines can read it without touching SwiftData
    /// off the main actor. `nil` or empty means "no design system context".
    @Published var designSystemSnapshot: DesignSystemSnapshot?

    /// The id of the design system currently driving generations. `"user"`
    /// (the default) means the user's own design system; any other value
    /// matches a `PublicDesignSystem.id` and applies that public system's
    /// style fragment instead.
    @Published var activeDesignSystemKey: String = PublicDesignSystem.userDesignSystemKey

    /// Bundled catalog of public design systems available for comparison.
    /// Loaded once on `AppState` init; failures are non-fatal and fall back
    /// to an empty catalog (the toggle UI hides itself in that case).
    let publicDesignSystemCatalog: [PublicDesignSystem]

    /// Published when a new generation should be persisted.
    /// ContentView observes this via `.onChange` to insert into the model context.
    @Published var pendingGeneration: Generation?

    init() {
        self.publicDesignSystemCatalog = (try? PublicDesignSystem.loadCatalog()) ?? []
    }

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

        let publicDS = publicDesignSystemForActiveKey()
        let key = activeDesignSystemKey

        Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
                    throw AIConversionPipeline.PipelineError.apiKeyMissing
                }
                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let pipeline = AIConversionPipeline(apiKey: apiKey, model: model)

                for try await state in pipeline.convertStreaming(
                    drawing: currentDrawing,
                    canvasSize: canvasSize,
                    designSystem: designSystemSnapshot,
                    publicDesignSystem: publicDS
                ) {
                    switch state {
                    case .generating(let partialText):
                        self.streamingText = partialText
                    case .completed(let result):
                        self.pushGeneratedResult(result, designSystemKey: key)
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

        let publicDS = publicDesignSystemForActiveKey()
        let key = activeDesignSystemKey

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
                    canvasSize: canvasSize,
                    designSystem: designSystemSnapshot,
                    publicDesignSystem: publicDS
                )
                self.pushGeneratedResult(result, designSystemKey: key)
            } catch {
                self.conversionError = error.localizedDescription
            }
            self.isRefining = false
        }
    }

    /// Switches the active design system, swapping the displayed result to a
    /// cached generation for the same drawing if one exists, or kicking off a
    /// fresh conversion otherwise.
    ///
    /// - Parameters:
    ///   - key: The new active key (`"user"` or a public-DS id).
    ///   - cachedGenerations: The current project's existing generations, in
    ///     reverse-chronological order. Provided by the view layer (which
    ///     owns the `@Query`) so `AppState` doesn't need a `ModelContext`.
    func setActiveDesignSystem(_ key: String, cachedGenerations: [Generation]) {
        guard key != activeDesignSystemKey else { return }
        activeDesignSystemKey = key

        // Look for an existing generation in this project that already used
        // the new key. We don't restrict by drawing — the user's most recent
        // result with that DS is good enough for an instant swap.
        if let cached = cachedGenerations.first(where: { $0.designSystemKey == key }) {
            generatedResult = GeneratedCode(
                htmlPreview: cached.htmlPreview,
                reactCode: cached.reactCode
            )
        } else {
            // No cache hit: trigger a fresh conversion using the active drawing.
            convertDrawing()
        }
    }

    /// Resolves the active key against the bundled catalog. Returns `nil` for
    /// the user-DS key or when the catalog couldn't be loaded.
    func publicDesignSystemForActiveKey() -> PublicDesignSystem? {
        guard activeDesignSystemKey != PublicDesignSystem.userDesignSystemKey else {
            return nil
        }
        return publicDesignSystemCatalog.first { $0.id == activeDesignSystemKey }
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
    private func pushGeneratedResult(
        _ result: GeneratedCode,
        designSystemKey: String = PublicDesignSystem.userDesignSystemKey
    ) {
        // If we navigated back and then generate a new result, discard forward history.
        if generationHistoryIndex < generationHistory.count - 1 {
            generationHistory = Array(generationHistory.prefix(generationHistoryIndex + 1))
        }
        generationHistory.append(result)
        generationHistoryIndex = generationHistory.count - 1
        generatedResult = result

        // Persist the generation to the project's history.
        saveGeneration(result, designSystemKey: designSystemKey)
    }

    /// Creates a `Generation` record and publishes it for the view layer to persist.
    private func saveGeneration(_ result: GeneratedCode, designSystemKey: String) {
        guard let project = currentProject else { return }
        let generation = Generation(
            htmlPreview: result.htmlPreview,
            reactCode: result.reactCode,
            drawingSnapshot: currentDrawing.dataRepresentation(),
            designSystemKey: designSystemKey,
            project: project
        )
        pendingGeneration = generation
    }
}
