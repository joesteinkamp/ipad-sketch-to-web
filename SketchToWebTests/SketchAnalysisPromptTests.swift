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

    // MARK: - User prompt without labels

    func testUserPromptWithoutLabelsIsUnchanged() {
        let prompt = SketchAnalysisPrompt.buildUserPrompt()
        XCTAssertEqual(
            prompt,
            "Convert this hand-drawn wireframe sketch into a web UI. Analyze each element and map it to the appropriate shadcn/ui component. Return valid JSON."
        )
    }

    func testEmptyLabelsArrayProducesIdenticalPrompt() {
        let withDefault = SketchAnalysisPrompt.buildUserPrompt()
        let withEmptyArray = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: [])
        XCTAssertEqual(withDefault, withEmptyArray)
    }

    // MARK: - User prompt with labels

    func testLabeledBoxesAppendAuthoritativeSection() {
        let box = LabeledBoxDetector.LabeledBox(
            bounds: CGRect(x: 120, y: 80, width: 300, height: 60),
            componentName: "Input",
            rawText: "input",
            confidence: 1.0
        )
        let prompt = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: [box])

        XCTAssertTrue(prompt.contains("# User-provided labels"))
        XCTAssertTrue(prompt.contains("ground truth"))
        XCTAssertTrue(prompt.contains("Box at (x:120, y:80, w:300, h:60): Input"))
    }

    func testMultipleLabelsAllAppearInPrompt() {
        let labels = [
            LabeledBoxDetector.LabeledBox(
                bounds: CGRect(x: 0, y: 0, width: 100, height: 40),
                componentName: "Button",
                rawText: "button",
                confidence: 1.0
            ),
            LabeledBoxDetector.LabeledBox(
                bounds: CGRect(x: 0, y: 60, width: 300, height: 200),
                componentName: "Card",
                rawText: "card",
                confidence: 1.0
            )
        ]
        let prompt = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: labels)

        XCTAssertTrue(prompt.contains("Box at (x:0, y:0, w:100, h:40): Button"))
        XCTAssertTrue(prompt.contains("Box at (x:0, y:60, w:300, h:200): Card"))
    }

    func testCoordinatesAreRoundedToIntegers() {
        let box = LabeledBoxDetector.LabeledBox(
            bounds: CGRect(x: 10.7, y: 20.4, width: 99.6, height: 33.2),
            componentName: "Badge",
            rawText: "badge",
            confidence: 1.0
        )
        let prompt = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: [box])
        XCTAssertTrue(prompt.contains("Box at (x:11, y:20, w:100, h:33): Badge"))
    }
}
