import XCTest
@testable import SketchToWeb

final class DesignSystemSynthesizerTests: XCTestCase {

    // MARK: - System prompt

    func testSystemPromptDeclaresRequiredSectionsAndRules() {
        let prompt = DesignSystemSynthesizer.buildSystemPrompt()

        // Section headers the synthesis is expected to produce.
        for header in [
            "## Brand Voice",
            "## Color Palette",
            "## Typography",
            "## Spacing & Radii",
            "## Component Conventions",
            "## Notes"
        ] {
            XCTAssertTrue(prompt.contains(header), "system prompt missing section: \(header)")
        }

        // Guardrails: no invented hex codes, plain markdown only.
        XCTAssertTrue(prompt.contains("Never invent hex codes."))
        XCTAssertTrue(prompt.contains("plain GitHub-flavored markdown"))
    }

    // MARK: - User text

    private func makeSnapshot(
        companyBlurb: String = "",
        notes: String = "",
        markdownContent: String? = nil,
        markdownFilename: String? = nil,
        sourceURL: String? = nil,
        sourceURLContent: String? = nil,
        zipExtractedContent: String? = nil,
        zipFilename: String? = nil,
        fontFileNames: [String] = [],
        assetFileNames: [String] = []
    ) -> DesignSystemSnapshot {
        DesignSystemSnapshot(
            companyBlurb: companyBlurb,
            notes: notes,
            markdownContent: markdownContent,
            markdownFilename: markdownFilename,
            sourceURL: sourceURL,
            sourceURLContent: sourceURLContent,
            zipExtractedContent: zipExtractedContent,
            zipFilename: zipFilename,
            fontFileNames: fontFileNames,
            assetFileNames: assetFileNames,
            synthesizedMarkdown: nil,
            synthesizedAt: nil
        )
    }

    func testUserTextOmitsEmptyBlocks() {
        let snap = makeSnapshot(companyBlurb: "Acme")
        let text = DesignSystemSynthesizer.buildUserText(snap)

        XCTAssertTrue(text.contains("# Company Blurb"))
        XCTAssertTrue(text.contains("Acme"))
        XCTAssertFalse(text.contains("# Existing DESIGN.md"))
        XCTAssertFalse(text.contains("# Source URL"))
        XCTAssertFalse(text.contains("# Zip"))
        XCTAssertFalse(text.contains("# Available Assets"))
        XCTAssertFalse(text.contains("# User Notes"))
    }

    func testUserTextSeparatesBlocksWithHorizontalRules() {
        let snap = makeSnapshot(
            companyBlurb: "Acme",
            notes: "earthy palette"
        )
        let text = DesignSystemSynthesizer.buildUserText(snap)

        XCTAssertTrue(text.contains("\n\n---\n\n"))
        // Blurb appears before notes (insertion order).
        let blurbIdx = text.range(of: "# Company Blurb")!.lowerBound
        let notesIdx = text.range(of: "# User Notes")!.lowerBound
        XCTAssertLessThan(blurbIdx, notesIdx)
    }

    func testUserTextLabelsSourceAndZipBlocks() {
        let snap = makeSnapshot(
            sourceURL: "https://github.com/acme/brand",
            sourceURLContent: "fetched content",
            zipExtractedContent: "extracted content",
            zipFilename: "design.zip"
        )
        let text = DesignSystemSynthesizer.buildUserText(snap)

        XCTAssertTrue(text.contains("# Source URL: https://github.com/acme/brand"))
        XCTAssertTrue(text.contains("# Zip: design.zip"))
    }

    func testUserTextListsAssetsWithoutPaths() {
        let snap = makeSnapshot(
            fontFileNames: ["Inter.ttf", "Display.otf"],
            assetFileNames: ["logo.svg"]
        )
        let text = DesignSystemSynthesizer.buildUserText(snap)

        XCTAssertTrue(text.contains("# Available Assets"))
        XCTAssertTrue(text.contains("- Fonts: Inter.ttf, Display.otf"))
        XCTAssertTrue(text.contains("- Logos/assets: logo.svg"))
    }

    func testUserTextTruncatesOversizedSources() {
        let huge = String(repeating: "z", count: DesignSystemSynthesizer.synthesisInputLimit + 5_000)
        let snap = makeSnapshot(
            sourceURL: "https://github.com/acme/brand",
            sourceURLContent: huge
        )
        let text = DesignSystemSynthesizer.buildUserText(snap)

        XCTAssertTrue(text.contains("[truncated]"))
        XCTAssertFalse(text.contains(huge))
    }
}
