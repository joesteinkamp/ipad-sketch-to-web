import Foundation

/// Constructs the prompts used to convert hand-drawn wireframe sketches into web UI code.
enum SketchAnalysisPrompt {

    /// Builds the system prompt that instructs the model how to interpret sketches and
    /// produce shadcn/ui component code.
    ///
    /// - Parameters:
    ///   - components: The component catalog describing available shadcn/ui components.
    ///   - designSystem: Optional design-system snapshot. When non-nil and non-empty,
    ///     a "Design System Context" section is inserted before layout rules so the
    ///     model can match the user's brand, tokens, and conventions.
    ///   - publicDesignSystem: Optional public design system to imitate (e.g.
    ///     Material 3). When non-nil and not the catalog default, its
    ///     `promptFragment` is appended *after* the user's design-system
    ///     section so the user's brand still wins on conflicts.
    /// - Returns: A fully formed system prompt string.
    static func buildSystemPrompt(
        components: [ComponentDefinition],
        designSystem: DesignSystemSnapshot? = nil,
        publicDesignSystem: PublicDesignSystem? = nil
    ) -> String {
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

        if let designSystemSection = buildDesignSystemSection(designSystem) {
            prompt += "\n" + designSystemSection
        }

        if let publicSection = buildPublicDesignSystemSection(publicDesignSystem) {
            prompt += "\n" + publicSection
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
    /// - Returns: A concise instruction string for the user message.
    static func buildUserPrompt() -> String {
        "Convert this hand-drawn wireframe sketch into a web UI. Analyze each element and map it to the appropriate shadcn/ui component. Return valid JSON."
    }

    /// Renders the design-system context as a prompt section. Returns `nil` when
    /// the snapshot is missing or empty so callers can omit the section entirely
    /// rather than emit an empty header.
    ///
    /// Long source content is truncated per-source so a single oversized import
    /// doesn't crowd out the rest of the prompt.
    static func buildDesignSystemSection(_ designSystem: DesignSystemSnapshot?) -> String? {
        guard let ds = designSystem, !ds.isEmpty else { return nil }

        var section = """
        # Design System Context
        Apply the following project-specific design guidance. When it conflicts \
        with shadcn/ui defaults, prefer this guidance for colors, typography, \
        spacing, and tone — but keep the underlying shadcn/ui component structure.


        """

        if !ds.companyBlurb.isEmpty {
            section += "## About\n\(ds.companyBlurb)\n\n"
        }

        if let markdown = ds.markdownContent, !markdown.isEmpty {
            let label = ds.markdownFilename ?? "DESIGN.md"
            section += "## Design Doc (`\(label)`)\n\(truncate(markdown, limit: 6000))\n\n"
        }

        if let urlText = ds.sourceURLContent, !urlText.isEmpty {
            let label = ds.sourceURL ?? "source"
            section += "## From \(label)\n\(truncate(urlText, limit: 4000))\n\n"
        }

        if let zipText = ds.zipExtractedContent, !zipText.isEmpty {
            let label = ds.zipFilename ?? "imported archive"
            section += "## From `\(label)`\n\(truncate(zipText, limit: 6000))\n\n"
        }

        if !ds.fontFileNames.isEmpty || !ds.assetFileNames.isEmpty {
            section += "## Available Assets\n"
            if !ds.fontFileNames.isEmpty {
                section += "- Fonts: \(ds.fontFileNames.joined(separator: ", "))\n"
            }
            if !ds.assetFileNames.isEmpty {
                section += "- Logos/assets: \(ds.assetFileNames.joined(separator: ", "))\n"
            }
            section += "\n"
        }

        if !ds.notes.isEmpty {
            section += "## Additional Notes\n\(ds.notes)\n\n"
        }

        return section
    }

    /// Renders the public-design-system section appended after the user's DS
    /// guidance. Returns `nil` for the catalog default (`shadcn`) and for an
    /// entry with an empty prompt fragment, so the prompt stays unchanged in
    /// the no-comparison case.
    static func buildPublicDesignSystemSection(_ publicDS: PublicDesignSystem?) -> String? {
        guard let publicDS, !publicDS.isDefault, !publicDS.promptFragment.isEmpty else {
            return nil
        }
        return """
        # Comparison Design System: \(publicDS.name)
        Apply the visual language of \(publicDS.name) to this generation. \
        If it conflicts with the user's own design system above, the user's \
        guidance still wins for brand-specific colors, copy, and tokens — but \
        adopt this system's component shapes, spacing, elevation, and \
        typography conventions.

        \(publicDS.promptFragment)


        """
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "\n\n... [truncated]"
    }
}
