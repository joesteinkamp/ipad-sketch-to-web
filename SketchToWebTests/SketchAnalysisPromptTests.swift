import XCTest
@testable import SketchToWeb

final class SketchAnalysisPromptTests: XCTestCase {

    // MARK: - Fixtures

    private let sampleComponents: [ComponentDefinition] = [
        ComponentDefinition(
            name: "Button",
            sketchPattern: "Rounded rectangle with text inside.",
            shadcnImport: "@/components/ui/button",
            exampleUsage: "<Button>Click</Button>"
        ),
        ComponentDefinition(
            name: "Card",
            sketchPattern: "Outlined rectangle containing other elements.",
            shadcnImport: "@/components/ui/card",
            exampleUsage: "<Card>...</Card>"
        )
    ]

    // MARK: - Component Catalog

    func testBuildSystemPromptIncludesAllComponents() {
        let prompt = SketchAnalysisPrompt.buildSystemPrompt(components: sampleComponents)

        XCTAssertTrue(prompt.contains("## Button"))
        XCTAssertTrue(prompt.contains("## Card"))
        XCTAssertTrue(prompt.contains("@/components/ui/button"))
        XCTAssertTrue(prompt.contains("@/components/ui/card"))
    }

    // MARK: - Design System Section

    func testBuildSystemPromptOmitsDesignSystemSectionWhenNil() {
        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: nil
        )

        XCTAssertFalse(prompt.contains("# Design System Context"))
    }

    func testBuildSystemPromptOmitsDesignSystemSectionWhenEmpty() {
        let empty = DesignSystemSnapshot(
            companyBlurb: "",
            notes: "",
            markdownContent: nil,
            markdownFilename: nil,
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            fontFileNames: [],
            assetFileNames: []
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: empty
        )

        XCTAssertFalse(prompt.contains("# Design System Context"))
    }

    func testBuildSystemPromptIncludesCompanyBlurb() {
        let snapshot = DesignSystemSnapshot(
            companyBlurb: "Acme Corp: friendly fintech for freelancers",
            notes: "",
            markdownContent: nil,
            markdownFilename: nil,
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            fontFileNames: [],
            assetFileNames: []
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: snapshot
        )

        XCTAssertTrue(prompt.contains("# Design System Context"))
        XCTAssertTrue(prompt.contains("## About"))
        XCTAssertTrue(prompt.contains("Acme Corp"))
    }

    func testBuildSystemPromptIncludesMarkdownContentAndFilename() {
        let snapshot = DesignSystemSnapshot(
            companyBlurb: "",
            notes: "",
            markdownContent: "# Brand\nUse warm earth tones.",
            markdownFilename: "DESIGN.md",
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            fontFileNames: [],
            assetFileNames: []
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: snapshot
        )

        XCTAssertTrue(prompt.contains("DESIGN.md"))
        XCTAssertTrue(prompt.contains("Use warm earth tones."))
    }

    func testBuildSystemPromptIncludesAssetNames() {
        let snapshot = DesignSystemSnapshot(
            companyBlurb: "",
            notes: "",
            markdownContent: nil,
            markdownFilename: nil,
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            fontFileNames: ["Inter.ttf", "Display.otf"],
            assetFileNames: ["logo.svg"]
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: snapshot
        )

        XCTAssertTrue(prompt.contains("Inter.ttf"))
        XCTAssertTrue(prompt.contains("Display.otf"))
        XCTAssertTrue(prompt.contains("logo.svg"))
    }

    func testBuildSystemPromptTruncatesLongMarkdown() {
        let huge = String(repeating: "x", count: 20_000)
        let snapshot = DesignSystemSnapshot(
            companyBlurb: "",
            notes: "",
            markdownContent: huge,
            markdownFilename: "DESIGN.md",
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            fontFileNames: [],
            assetFileNames: []
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: snapshot
        )

        XCTAssertTrue(prompt.contains("[truncated]"))
        // The full 20k-character string should not be embedded verbatim.
        XCTAssertFalse(prompt.contains(huge))
    }

    func testDesignSystemSectionPlacedBeforeLayoutRules() {
        let snapshot = DesignSystemSnapshot(
            companyBlurb: "Acme",
            notes: "",
            markdownContent: nil,
            markdownFilename: nil,
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            fontFileNames: [],
            assetFileNames: []
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: snapshot
        )

        guard
            let designIdx = prompt.range(of: "# Design System Context")?.lowerBound,
            let layoutIdx = prompt.range(of: "# Layout Interpretation Rules")?.lowerBound
        else {
            XCTFail("Expected both sections in prompt")
            return
        }

        XCTAssertLessThan(designIdx, layoutIdx)
    }
}
