import Foundation

/// Distills the user's raw design-system inputs (blurb, fetched DESIGN.md /
/// README, zip-extracted snippets, notes, asset filenames) into a single
/// focused DESIGN.md via a one-shot Gemini call. The result is persisted on
/// `DesignSystem.synthesizedMarkdown` and replaces the raw blocks in the
/// conversion prompt.
struct DesignSystemSynthesizer {

    enum SynthesisError: LocalizedError {
        case apiKeyMissing
        case noInputs
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "Add a Gemini API key in Settings first."
            case .noInputs:
                return "Add a blurb, URL, zip, or notes before synthesizing."
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    let apiKey: String
    let model: String

    /// Runs synthesis. Returns the model's plain-markdown response.
    func synthesize(_ snapshot: DesignSystemSnapshot) async throws -> String {
        guard !apiKey.isEmpty else { throw SynthesisError.apiKeyMissing }
        guard !snapshot.isEmpty else { throw SynthesisError.noInputs }

        let client = GeminiClient(apiKey: apiKey, model: model)
        let systemPrompt = Self.buildSystemPrompt()
        let userText = Self.buildUserText(snapshot)
        do {
            return try await client.sendTextMessage(
                systemPrompt: systemPrompt,
                userText: userText
            )
        } catch {
            throw SynthesisError.underlying(error)
        }
    }

    // MARK: - Prompt Builders

    static func buildSystemPrompt() -> String {
        """
        You are a senior design-system editor. Distill the provided raw inputs into a \
        clean DESIGN.md (~2–3k chars) that will be used as context when generating UI code.

        Required sections (omit a section only when the inputs contain zero evidence for it):
        ## Brand Voice
        ## Color Palette          (concrete hex/HSL values only when explicitly present in inputs; otherwise describe qualitatively)
        ## Typography             (font families, scale, weights — only what appears in inputs)
        ## Spacing & Radii
        ## Component Conventions  (button styles, cards, form patterns)
        ## Notes

        Rules:
        - Ground every claim in the provided inputs.
        - Prefix any inferred value with "Inferred:" so it can be flagged later.
        - Never invent hex codes. If a palette is described qualitatively ("warm earthy"), keep it qualitative.
        - Output plain GitHub-flavored markdown only. No code fences around the whole document, no preamble, no JSON.
        """
    }

    /// Concatenates only non-empty input blocks, separated by a horizontal rule
    /// so the model can tell where one source ends and the next begins.
    static func buildUserText(_ s: DesignSystemSnapshot) -> String {
        var blocks: [String] = []

        if !s.companyBlurb.isEmpty {
            blocks.append("# Company Blurb\n\(s.companyBlurb)")
        }

        if let presetBody = s.presetContent, !presetBody.isEmpty {
            let label = s.presetName ?? "Preset"
            blocks.append("# Active Preset: \(label)\n\(truncate(presetBody, limit: synthesisInputLimit))")
        }

        if let md = s.markdownContent, !md.isEmpty {
            let label = s.markdownFilename ?? "DESIGN.md"
            blocks.append("# Existing DESIGN.md (`\(label)`)\n\(truncate(md, limit: synthesisInputLimit))")
        }

        if let urlText = s.sourceURLContent, !urlText.isEmpty {
            let label = s.sourceURL ?? "source"
            blocks.append("# Source URL: \(label)\n\(truncate(urlText, limit: synthesisInputLimit))")
        }

        if let zipText = s.zipExtractedContent, !zipText.isEmpty {
            let label = s.zipFilename ?? "imported archive"
            blocks.append("# Zip: \(label)\n\(truncate(zipText, limit: synthesisInputLimit))")
        }

        if !s.fontFileNames.isEmpty || !s.assetFileNames.isEmpty {
            var assets = "# Available Assets\n"
            if !s.fontFileNames.isEmpty {
                assets += "- Fonts: \(s.fontFileNames.joined(separator: ", "))\n"
            }
            if !s.assetFileNames.isEmpty {
                assets += "- Logos/assets: \(s.assetFileNames.joined(separator: ", "))\n"
            }
            blocks.append(assets.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if !s.notes.isEmpty {
            blocks.append("# User Notes\n\(s.notes)")
        }

        return blocks.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Internals

    /// Per-source budget. More generous than the per-section limits in
    /// `SketchAnalysisPrompt` because synthesis is a single Gemini call rather
    /// than one block of a larger prompt.
    static let synthesisInputLimit = 10_000

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "\n\n... [truncated]"
    }
}
