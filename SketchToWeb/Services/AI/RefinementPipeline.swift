import Foundation

/// Handles iterative refinement of generated UI code based on user annotations.
///
/// The user draws red annotations (circles, arrows, handwritten notes) on top of
/// the current preview. This pipeline sends the annotated screenshot plus the
/// existing code to the Gemini API so the model can apply the requested changes.
final class RefinementPipeline: Sendable {

    // MARK: - Errors

    enum RefinementError: LocalizedError {
        case apiKeyMissing
        case emptyAnnotationImage

        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "Gemini API key is not configured. Please add your key in Settings."
            case .emptyAnnotationImage:
                return "The annotation screenshot is empty."
            }
        }
    }

    // MARK: - Properties

    let client: GeminiClient

    // MARK: - Initialization

    init(apiKey: String, model: String = "gemini-3.1-pro-preview") {
        self.client = GeminiClient(apiKey: apiKey, model: model)
    }

    // MARK: - Refinement

    /// Refines existing generated code based on an annotated screenshot.
    ///
    /// - Parameters:
    ///   - currentCode: The current `GeneratedCode` that the user is refining.
    ///   - annotationImage: PNG data of the composite screenshot (web preview + red annotations).
    ///   - canvasSize: The size of the preview area.
    ///   - designSystem: Optional design-system snapshot to inject into the prompt
    ///     so refinements stay consistent with the user's brand and tokens.
    /// - Returns: An updated `GeneratedCode` reflecting the user's requested changes.
    /// - Throws: `RefinementError` or `GeminiClient.GeminiError` on failure.
    func refine(
        currentCode: GeneratedCode,
        annotationImage: Data,
        canvasSize: CGSize,
        designSystem: DesignSystemSnapshot? = nil,
        publicDesignSystem: PublicDesignSystem? = nil
    ) async throws -> GeneratedCode {
        guard !annotationImage.isEmpty else {
            throw RefinementError.emptyAnnotationImage
        }

        let systemPrompt = buildRefinementSystemPrompt(
            designSystem: designSystem,
            publicDesignSystem: publicDesignSystem
        )
        let userPrompt = buildRefinementUserPrompt(currentCode: currentCode, canvasSize: canvasSize)

        let responseText = try await client.sendMessage(
            systemPrompt: systemPrompt,
            imageData: annotationImage,
            userText: userPrompt
        )

        let generatedCode = try CodeGenerationResponse.parse(responseText)
        return generatedCode
    }

    // MARK: - Prompt Construction

    private func buildRefinementSystemPrompt(
        designSystem: DesignSystemSnapshot? = nil,
        publicDesignSystem: PublicDesignSystem? = nil
    ) -> String {
        var prompt = """
        You are refining an existing UI. The image shows the current UI with red annotations \
        drawn on top by the user using Apple Pencil.

        Red circles, arrows, and handwritten notes indicate changes the user wants. \
        Analyze the annotations carefully and modify the code accordingly.

        # How to Interpret Annotations
        - **Red circles** around an element: The user wants that specific element changed. \
        Look for nearby handwritten text to understand what change is requested.
        - **Red arrows** pointing to an element: Similar to circles — the arrow target is what \
        needs to change. Follow the arrow from the annotation text to the target element.
        - **Handwritten red text**: Instructions like "make this bigger", "change to blue", \
        "add padding", "remove this", "move left", etc. Apply these changes to the nearest \
        circled or arrowed element.
        - **Red X marks or strikethrough**: The user wants that element removed.
        - **Red lines or boxes** drawn where no element exists: The user wants a new element \
        added in that location.

        # Rules
        - Preserve ALL existing UI elements and styling that are NOT annotated.
        - Only modify the parts of the code that correspond to annotated areas.
        - Maintain the same overall layout structure unless annotations explicitly request layout changes.
        - Use Tailwind CSS utility classes for all styling changes.
        - Keep shadcn/ui component usage consistent with the existing code.

        # Output Format
        You MUST respond with valid JSON containing exactly two keys:

        ```json
        {
          "htmlPreview": "...",
          "reactCode": "..."
        }
        ```

        ## htmlPreview
        A complete, self-contained HTML document (same format as the original). Include \
        `<script src="https://cdn.tailwindcss.com"></script>` in the `<head>`.

        ## reactCode
        A single Next.js React component file using shadcn/ui components.

        # Important
        - Output ONLY the JSON object. No markdown code fences, no explanation, no commentary.
        - Ensure both values are valid strings with properly escaped characters.
        - The refined code should be a complete replacement, not a diff or partial update.
        """

        if let section = SketchAnalysisPrompt.buildDesignSystemSection(designSystem) {
            prompt += "\n\n" + section
        }

        if let publicSection = SketchAnalysisPrompt.buildPublicDesignSystemSection(publicDesignSystem) {
            prompt += "\n\n" + publicSection
        }

        return prompt
    }

    private func buildRefinementUserPrompt(currentCode: GeneratedCode, canvasSize: CGSize) -> String {
        """
        The image shows my current UI preview with red annotations I drew on top to indicate \
        changes I want. Please refine the code based on my annotations.

        The preview area is \(Int(canvasSize.width))x\(Int(canvasSize.height)) points.

        Here is the current React code that generated the preview shown in the image:

        ```jsx
        \(currentCode.reactCode)
        ```

        Here is the current HTML preview code:

        ```html
        \(currentCode.htmlPreview)
        ```

        Analyze my red annotations on the screenshot and return updated JSON with both \
        htmlPreview and reactCode reflecting the changes I requested.
        """
    }
}
