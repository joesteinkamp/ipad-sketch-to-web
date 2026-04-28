import Foundation

/// Constructs the prompts used to convert hand-drawn wireframe sketches into web UI code.
enum SketchAnalysisPrompt {

    /// Builds the system prompt that instructs the model how to interpret sketches and
    /// produce shadcn/ui component code.
    ///
    /// - Parameter components: The component catalog describing available shadcn/ui components.
    /// - Returns: A fully formed system prompt string.
    static func buildSystemPrompt(components: [ComponentDefinition]) -> String {
        var prompt = """
        You are an expert UI developer who specializes in converting hand-drawn wireframe \
        sketches into production-quality web interfaces using shadcn/ui components and Tailwind CSS.

        # Your Task
        Analyze the provided wireframe image and produce two outputs:
        1. A self-contained HTML preview
        2. A Next.js React component using shadcn/ui

        # Available shadcn/ui Components
        Below are the components you can use. Match hand-drawn elements to the most appropriate component \
        based on visual patterns:

        """

        for component in components {
            prompt += """

            ## \(component.name)
            - **Visual pattern**: \(component.sketchPattern)
            - **Import**: `import { \(component.name) } from "\(component.shadcnImport)"`
            - **Example**: `\(component.exampleUsage)`

            """
        }

        prompt += """

        # Layout Interpretation Rules
        - Interpret relative positions of drawn elements to determine layout structure (rows, columns, grids).
        - Horizontal alignment of elements implies a flex row; vertical stacking implies a flex column.
        - Estimate spacing from the gaps between drawn elements. Use Tailwind spacing utilities (gap-2, gap-4, etc.).
        - Interpret relative sizes proportionally. Larger drawn rectangles should map to wider/taller components.
        - Drawn borders or boxes typically indicate Card or container components.
        - Lines connecting elements suggest navigation or flow, not visual elements.
        - Text written inside shapes should become the label or content of the corresponding component.

        # Styling Rules
        - Use Tailwind CSS utility classes for ALL styling. Do not use inline styles or custom CSS.
        - Apply appropriate responsive breakpoints where the layout clearly implies responsiveness.
        - Use shadcn/ui default variants unless the sketch clearly indicates a specific variant (e.g., outline button vs filled button).
        - Maintain consistent spacing and alignment using Tailwind's spacing scale.

        # Output Format
        You MUST respond with valid JSON containing exactly two keys:

        ```json
        {
          "htmlPreview": "...",
          "reactCode": "..."
        }
        ```

        ## htmlPreview
        A complete, self-contained HTML document that can be rendered directly in a web view. Requirements:
        - Include `<script src="https://cdn.tailwindcss.com"></script>` in the `<head>`.
        - Style components to visually match shadcn/ui defaults (rounded corners, proper padding, neutral color palette).
        - Use Tailwind classes for all styling.
        - The HTML should be a faithful visual representation of what the React component would render.
        - Include a proper `<!DOCTYPE html>` declaration and viewport meta tag.

        ## reactCode
        A single Next.js React component file. Requirements:
        - Use "use client" directive at the top if the component uses any client-side features.
        - Import shadcn/ui components from `@/components/ui/` (e.g., `import { Button } from "@/components/ui/button"`).
        - Export the component as a default export.
        - Use TypeScript syntax.
        - Use Tailwind classes for layout and custom styling.
        - Include proper prop types if the component accepts props.

        # Important
        - Output ONLY the JSON object. No markdown code fences, no explanation, no commentary.
        - Ensure both values are valid strings with properly escaped characters.
        - If an element in the sketch is ambiguous, choose the most common UI interpretation.
        """

        return prompt
    }

    /// Builds the user-facing prompt that accompanies the wireframe image.
    ///
    /// - Parameter labeledBoxes: Boxes the user explicitly tagged by writing a component name
    ///   inside them. When non-empty, an authoritative-labels section is appended so the
    ///   model treats those classifications as ground truth.
    /// - Returns: A concise instruction string for the user message.
    static func buildUserPrompt(labeledBoxes: [LabeledBoxDetector.LabeledBox] = []) -> String {
        let base = "Convert this hand-drawn wireframe sketch into a web UI. Analyze each element and map it to the appropriate shadcn/ui component. Return valid JSON."

        guard !labeledBoxes.isEmpty else { return base }

        var labelSection = """


        # User-provided labels
        The user has explicitly labeled the following components by writing the component name inside the box. Treat these as ground truth — do not reclassify these elements:
        """

        for box in labeledBoxes {
            let x = Int(box.bounds.origin.x.rounded())
            let y = Int(box.bounds.origin.y.rounded())
            let w = Int(box.bounds.width.rounded())
            let h = Int(box.bounds.height.rounded())
            labelSection += "\n- Box at (x:\(x), y:\(y), w:\(w), h:\(h)): \(box.componentName)"
        }

        return base + labelSection
    }
}
