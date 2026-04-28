import Foundation
import PencilKit
import UIKit

/// Orchestrates the end-to-end conversion of a PencilKit drawing into generated web code.
///
/// Steps:
/// 1. Render the drawing onto a white background and export as PNG.
/// 2. Load the shadcn/ui component catalog.
/// 3. Build system and user prompts.
/// 4. Send the image and prompts to the Gemini API.
/// 5. Parse the response into a `GeneratedCode` value.
final class AIConversionPipeline: Sendable {

    // MARK: - Errors

    enum PipelineError: LocalizedError {
        case imageRenderingFailed
        case apiKeyMissing

        var errorDescription: String? {
            switch self {
            case .imageRenderingFailed:
                return "Failed to render the drawing as a PNG image."
            case .apiKeyMissing:
                return "Gemini API key is not configured. Please add your key in Settings."
            }
        }
    }

    // MARK: - Streaming State

    /// Represents the progression of a streaming conversion.
    enum StreamingState {
        /// The model is still generating; `partialText` is the accumulated raw text so far.
        case generating(partialText: String)
        /// Generation is complete and the final text has been parsed into `GeneratedCode`.
        case completed(GeneratedCode)
    }

    // MARK: - Properties

    let client: GeminiClient

    // MARK: - Initialization

    /// Creates a new pipeline with the given API key.
    ///
    /// - Parameter apiKey: Your Google AI / Gemini API key.
    /// - Parameter model: Optional model override. Defaults to the client's default model.
    init(apiKey: String, model: String = "gemini-3.1-pro-preview") {
        self.client = GeminiClient(apiKey: apiKey, model: model)
    }

    // MARK: - Conversion

    /// Converts a PencilKit drawing into generated web code.
    ///
    /// - Parameters:
    ///   - drawing: The PencilKit drawing to convert.
    ///   - canvasSize: The size of the canvas the drawing was created on.
    ///   - designSystem: Optional design-system snapshot to inject into the prompt.
    ///   - publicDesignSystem: Optional public DS to imitate (e.g. Material 3).
    /// - Returns: A `GeneratedCode` value containing the HTML preview and React source.
    /// - Throws: `PipelineError` or `GeminiClient.GeminiError` on failure.
    @MainActor
    func convert(
        drawing: PKDrawing,
        canvasSize: CGSize,
        designSystem: DesignSystemSnapshot? = nil,
        publicDesignSystem: PublicDesignSystem? = nil
    ) async throws -> GeneratedCode {
        // Step 1: Render the drawing onto a white background and export as PNG.
        let pngData = try renderDrawingAsPNG(drawing: drawing, canvasSize: canvasSize)

        // Step 2: Load the component catalog.
        let components = try ComponentDefinition.loadCatalog()

        // Step 3: Build prompts.
        let systemPrompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: components,
            designSystem: designSystem,
            publicDesignSystem: publicDesignSystem
        )
        let userPrompt = SketchAnalysisPrompt.buildUserPrompt()

        // Step 4: Send to Gemini API.
        let responseText = try await client.sendMessage(
            systemPrompt: systemPrompt,
            imageData: pngData,
            userText: userPrompt
        )

        // Step 5: Parse the response.
        let generatedCode = try CodeGenerationResponse.parse(responseText)
        return generatedCode
    }

    // MARK: - Streaming Conversion

    /// Converts a PencilKit drawing into generated web code using streaming,
    /// yielding partial text as the model generates it.
    ///
    /// - Parameters:
    ///   - drawing: The PencilKit drawing to convert.
    ///   - canvasSize: The size of the canvas the drawing was created on.
    ///   - designSystem: Optional design-system snapshot to inject into the prompt.
    ///   - publicDesignSystem: Optional public DS to imitate (e.g. Material 3).
    /// - Returns: An `AsyncThrowingStream` of `StreamingState` values.
    @MainActor
    func convertStreaming(
        drawing: PKDrawing,
        canvasSize: CGSize,
        designSystem: DesignSystemSnapshot? = nil,
        publicDesignSystem: PublicDesignSystem? = nil
    ) -> AsyncThrowingStream<StreamingState, Error> {
        // Capture rendering and prompt construction on the main actor before entering the stream.
        let pngData: Data
        let systemPrompt: String
        let userPrompt: String

        do {
            pngData = try renderDrawingAsPNG(drawing: drawing, canvasSize: canvasSize)
            let components = try ComponentDefinition.loadCatalog()
            systemPrompt = SketchAnalysisPrompt.buildSystemPrompt(
                components: components,
                designSystem: designSystem,
                publicDesignSystem: publicDesignSystem
            )
            userPrompt = SketchAnalysisPrompt.buildUserPrompt()
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let client = self.client

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var finalText = ""
                    for try await accumulated in client.streamMessage(
                        systemPrompt: systemPrompt,
                        imageData: pngData,
                        userText: userPrompt
                    ) {
                        finalText = accumulated
                        continuation.yield(.generating(partialText: accumulated))
                    }

                    let generatedCode = try CodeGenerationResponse.parse(finalText)
                    continuation.yield(.completed(generatedCode))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Drawing Rendering

    /// Renders a PencilKit drawing composited onto a white background and exports it as PNG data.
    ///
    /// PencilKit drawings render with a transparent background by default, so we composite
    /// the drawing onto a white rectangle to produce a clean image for the vision model.
    @MainActor
    private func renderDrawingAsPNG(drawing: PKDrawing, canvasSize: CGSize) throws -> Data {
        let rect = CGRect(origin: .zero, size: canvasSize)
        let scale: CGFloat = min(UIScreen.main.scale, 2.0) // Cap at 2x to limit payload size.

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { context in
            // White background.
            UIColor.white.setFill()
            context.fill(rect)

            // Composite the PencilKit strokes on top.
            let drawingImage = drawing.image(from: rect, scale: scale)
            drawingImage.draw(in: rect)
        }

        guard let pngData = image.pngData() else {
            throw PipelineError.imageRenderingFailed
        }

        return pngData
    }
}
