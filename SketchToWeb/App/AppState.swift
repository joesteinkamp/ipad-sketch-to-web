import Foundation
import PencilKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isConverting = false
    @Published var isRefining = false
    @Published var error: AppError?
    @Published var generatedResult: GeneratedCode?
    @Published var streamingText: String?

    /// History of generated code versions for back/forward navigation.
    @Published private(set) var history = GenerationHistory()

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

    /// Published when a new generation should be persisted.
    /// ContentView observes this via `.onChange` to insert into the model context.
    @Published var pendingGeneration: Generation?

    // MARK: - Design Export

    /// Active state of an in-flight export to a remote design tool. `nil` when
    /// no export is running. Views observing this drive a progress sheet.
    @Published var designExportState: DesignExportState?

    /// Whether the user currently has a stored Figma OAuth token.
    /// Refreshed on app launch and after connect/disconnect.
    @Published var figmaConnected: Bool = KeychainHelper.loadOAuthTokens(for: .figma) != nil

    // MARK: - Source-Compatible Bridges

    /// Read-only bridge so existing views (`PreviewContainerView`) keep compiling.
    var generationHistory: [GeneratedCode] { history.versions }

    /// Read-only bridge so existing views keep compiling.
    var generationHistoryIndex: Int { history.index }

    /// Whether the user can navigate back in generation history.
    var canGoBack: Bool { history.canGoBack }

    /// Whether the user can navigate forward in generation history.
    var canGoForward: Bool { history.canGoForward }

    /// Read/clear bridge for `ContentView`'s error banner. Setting to `nil`
    /// clears the underlying typed error; non-nil writes are ignored.
    var conversionError: String? {
        get { error?.errorDescription }
        set { if newValue == nil { error = nil } }
    }

    // MARK: - Dependencies

    typealias ConversionPipelineFactory = @MainActor (String, String) -> AIConversionPipeline
    typealias RefinementPipelineFactory = @Sendable (String, String) -> RefinementPipeline
    typealias APIKeyProvider = @Sendable () -> String?

    private let makeConversionPipeline: ConversionPipelineFactory
    private let makeRefinementPipeline: RefinementPipelineFactory
    private let apiKeyProvider: APIKeyProvider

    init(
        makeConversionPipeline: @escaping ConversionPipelineFactory = { AIConversionPipeline.live(apiKey: $0, model: $1) },
        makeRefinementPipeline: @escaping RefinementPipelineFactory = { RefinementPipeline.live(apiKey: $0, model: $1) },
        apiKeyProvider: @escaping APIKeyProvider = { KeychainHelper.loadAPIKey() }
    ) {
        self.makeConversionPipeline = makeConversionPipeline
        self.makeRefinementPipeline = makeRefinementPipeline
        self.apiKeyProvider = apiKeyProvider
    }

    // MARK: - Conversion

    /// Converts the current drawing using the AI pipeline.
    /// Called from the toolbar's Convert button (no arguments needed).
    func convertDrawing() {
        guard !isConverting else { return }

        isConverting = true
        error = nil
        streamingText = nil

        let drawing = currentDrawing
        let canvasSize = canvasSize
        let designSystem = designSystemSnapshot

        Task {
            do {
                guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                    throw AppError.apiKeyMissing
                }
                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let pipeline = makeConversionPipeline(apiKey, model)

                for try await state in await pipeline.convertStreaming(
                    drawing: drawing,
                    canvasSize: canvasSize,
                    designSystem: designSystem
                ) {
                    switch state {
                    case .generating(let partialText):
                        self.streamingText = partialText
                    case .completed(let result):
                        self.pushGeneratedResult(result)
                        self.streamingText = nil
                    }
                }
            } catch {
                self.error = AppError(error)
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
    ///   - comments: Optional typed comments keyed to numbered pins drawn on the screenshot
    ///     (e.g. `"Pin 1: change this to blue"`). Empty when the user only used freehand strokes.
    func refineResult(annotationImage: Data, canvasSize: CGSize, comments: [String] = []) {
        guard !isRefining, let currentCode = generatedResult else { return }

        isRefining = true
        error = nil

        let designSystem = designSystemSnapshot

        Task {
            do {
                guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                    throw AppError.apiKeyMissing
                }
                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let pipeline = makeRefinementPipeline(apiKey, model)
                let result = try await pipeline.refine(
                    currentCode: currentCode,
                    annotationImage: annotationImage,
                    canvasSize: canvasSize,
                    comments: comments,
                    designSystem: designSystem
                )
                self.pushGeneratedResult(result)
            } catch {
                self.error = AppError(error)
            }
            self.isRefining = false
        }
    }

    /// Rehydrates `generatedResult` and `history` from a project's persisted
    /// generations so reopening a project doesn't require another API call.
    ///
    /// History is rebuilt in chronological order from `project.generations`,
    /// falling back to the legacy `generatedHTML` / `generatedReactCode`
    /// fields for projects created before the `Generation` model existed.
    func loadStoredResult(for project: Project?) {
        streamingText = nil
        error = nil

        guard let project else {
            history = GenerationHistory()
            generatedResult = nil
            return
        }

        var restored = GenerationHistory()
        for generation in project.generations.sorted(by: { $0.createdAt < $1.createdAt }) {
            restored.push(GeneratedCode(
                htmlPreview: generation.htmlPreview,
                reactCode: generation.reactCode
            ))
        }

        if restored.isEmpty,
           let html = project.generatedHTML,
           let react = project.generatedReactCode {
            restored.push(GeneratedCode(htmlPreview: html, reactCode: react))
        }

        history = restored
        generatedResult = restored.current
    }

    // MARK: - History Navigation

    /// Navigates to the previous version in generation history.
    func goBack() {
        if let previous = history.goBack() {
            generatedResult = previous
        }
    }

    /// Navigates to the next version in generation history.
    func goForward() {
        if let next = history.goForward() {
            generatedResult = next
        }
    }

    // MARK: - Design Tool OAuth

    /// Starts the Figma OAuth flow and updates `figmaConnected` on success.
    func connectFigma() async throws {
        _ = try await FigmaOAuth.shared.connect()
        self.figmaConnected = true
    }

    /// Clears stored Figma tokens and updates `figmaConnected`.
    func disconnectFigma() {
        FigmaOAuth.shared.disconnect()
        self.figmaConnected = false
    }

    // MARK: - Design Tool Export

    /// Sends the original sketch + currently displayed generated code to the
    /// given destination via its remote MCP. Streams progress into
    /// `designExportState`.
    ///
    /// - Parameters:
    ///   - destination: The design tool to export to.
    ///   - userInstruction: Optional free-form note (e.g. "make it dark").
    func exportToDesignTool(destination: DesignDestination, userInstruction: String? = nil) {
        guard let result = generatedResult else { return }

        designExportState = .connecting

        Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
                    throw DesignExportPipeline.ExportError.geminiKeyMissing
                }
                guard KeychainHelper.loadOAuthTokens(for: destination) != nil else {
                    throw DesignExportPipeline.ExportError.notConnected(destination)
                }
                guard let pngData = DrawingExporter.exportAsPNGData(currentDrawing, canvasSize: canvasSize) else {
                    throw AIConversionPipeline.PipelineError.imageRenderingFailed
                }

                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let pipeline = DesignExportPipeline(
                    destination: destination,
                    geminiAPIKey: apiKey,
                    geminiModel: model
                )

                for try await state in pipeline.run(
                    sketchPNG: pngData,
                    generatedCode: result,
                    userInstruction: userInstruction
                ) {
                    self.designExportState = state
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.designExportState = .failed(message: message)
            }
        }
    }

    /// Clears any in-flight or terminal export state. Used by the sheet on dismiss.
    func resetDesignExportState() {
        designExportState = nil
    }

    // MARK: - Private Helpers

    /// Pushes a new result onto the history stack and updates the current result.
    private func pushGeneratedResult(_ result: GeneratedCode) {
        history.push(result)
        generatedResult = result
        saveGeneration(result)
    }

    /// Creates a `Generation` record and publishes it for the view layer to persist.
    /// Also caches the latest output on the `Project` itself so reopening the
    /// project restores the preview without re-running the model.
    private func saveGeneration(_ result: GeneratedCode) {
        guard let project = currentProject else { return }
        project.generatedHTML = result.htmlPreview
        project.generatedReactCode = result.reactCode
        let generation = Generation(
            htmlPreview: result.htmlPreview,
            reactCode: result.reactCode,
            drawingSnapshot: currentDrawing.dataRepresentation(),
            project: project
        )
        pendingGeneration = generation
    }
}
