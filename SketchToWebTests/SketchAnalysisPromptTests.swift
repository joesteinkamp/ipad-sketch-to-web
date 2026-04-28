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

    // MARK: - Public Design System Section

    func testBuildSystemPromptOmitsPublicSectionForDefaultEntry() {
        let shadcn = PublicDesignSystem(
            id: "shadcn",
            name: "shadcn/ui",
            shortName: "shadcn",
            description: "",
            isDefault: true,
            promptFragment: ""
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            publicDesignSystem: shadcn
        )

        XCTAssertFalse(prompt.contains("Comparison Design System"))
    }

    func testBuildSystemPromptIncludesPublicSectionForNonDefaultEntry() {
        let material = PublicDesignSystem(
            id: "material-3",
            name: "Material 3",
            shortName: "Material 3",
            description: "",
            isDefault: false,
            promptFragment: "Use Material 3 elevation tokens."
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            publicDesignSystem: material
        )

        XCTAssertTrue(prompt.contains("# Comparison Design System: Material 3"))
        XCTAssertTrue(prompt.contains("Use Material 3 elevation tokens."))
    }

    func testPublicSectionFollowsUserDesignSystemSection() {
        let userDS = DesignSystemSnapshot(
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
        let material = PublicDesignSystem(
            id: "material-3",
            name: "Material 3",
            shortName: "Material 3",
            description: "",
            isDefault: false,
            promptFragment: "Material 3 fragment."
        )

        let prompt = SketchAnalysisPrompt.buildSystemPrompt(
            components: sampleComponents,
            designSystem: userDS,
            publicDesignSystem: material
        )

        guard
            let userIdx = prompt.range(of: "# Design System Context")?.lowerBound,
            let publicIdx = prompt.range(of: "# Comparison Design System: Material 3")?.lowerBound,
            let layoutIdx = prompt.range(of: "# Layout Interpretation Rules")?.lowerBound
        else {
            XCTFail("Expected all three sections in prompt")
            return
        }
        XCTAssertLessThan(userIdx, publicIdx, "User DS must come before public DS so user wins on conflicts")
        XCTAssertLessThan(publicIdx, layoutIdx, "Public DS must come before layout rules")
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
