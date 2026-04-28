import XCTest
@testable import SketchToWeb

final class ComponentLabelMatcherTests: XCTestCase {

    private let catalog: [ComponentDefinition] = [
        .init(name: "Button", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Input", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Card", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Textarea", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Select", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "NavigationMenu", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "RadioGroup", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Separator", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Switch", sketchPattern: "", shadcnImport: "", exampleUsage: ""),
        .init(name: "Badge", sketchPattern: "", shadcnImport: "", exampleUsage: "")
    ]

    // MARK: - Exact catalog hits

    func testMatchesExactCatalogNameLowercase() {
        XCTAssertEqual(ComponentLabelMatcher.match("button", catalog: catalog)?.componentName, "Button")
    }

    func testMatchesExactCatalogNameTitleCase() {
        XCTAssertEqual(ComponentLabelMatcher.match("Button", catalog: catalog)?.componentName, "Button")
    }

    func testMatchesExactCatalogNameUppercase() {
        XCTAssertEqual(ComponentLabelMatcher.match("BUTTON", catalog: catalog)?.componentName, "Button")
    }

    // MARK: - Punctuation and whitespace

    func testStripsPunctuation() {
        XCTAssertEqual(ComponentLabelMatcher.match("BUTTON!", catalog: catalog)?.componentName, "Button")
    }

    func testStripsTrailingColon() {
        XCTAssertEqual(ComponentLabelMatcher.match("input:", catalog: catalog)?.componentName, "Input")
    }

    func testStripsInternalWhitespace() {
        XCTAssertEqual(ComponentLabelMatcher.match("text area", catalog: catalog)?.componentName, "Textarea")
    }

    // MARK: - Aliases

    func testButtonAlias() {
        XCTAssertEqual(ComponentLabelMatcher.match("btn", catalog: catalog)?.componentName, "Button")
    }

    func testDropdownAlias() {
        XCTAssertEqual(ComponentLabelMatcher.match("dropdown", catalog: catalog)?.componentName, "Select")
    }

    func testNavAlias() {
        XCTAssertEqual(ComponentLabelMatcher.match("nav", catalog: catalog)?.componentName, "NavigationMenu")
    }

    func testRadioAlias() {
        XCTAssertEqual(ComponentLabelMatcher.match("radio", catalog: catalog)?.componentName, "RadioGroup")
    }

    func testToggleAlias() {
        XCTAssertEqual(ComponentLabelMatcher.match("toggle", catalog: catalog)?.componentName, "Switch")
    }

    func testDividerAlias() {
        XCTAssertEqual(ComponentLabelMatcher.match("divider", catalog: catalog)?.componentName, "Separator")
    }

    // MARK: - Typo tolerance

    func testAcceptsSingleCharTypoOnLongWord() {
        // "buton" → "button" (distance 1)
        XCTAssertEqual(ComponentLabelMatcher.match("buton", catalog: catalog)?.componentName, "Button")
    }

    func testAcceptsSingleCharTypoOnTextarea() {
        // "textara" → "textarea" (distance 1)
        XCTAssertEqual(ComponentLabelMatcher.match("textara", catalog: catalog)?.componentName, "Textarea")
    }

    // MARK: - Rejection

    func testRejectsUnrelatedWord() {
        XCTAssertNil(ComponentLabelMatcher.match("hello", catalog: catalog))
    }

    func testRejectsEmptyString() {
        XCTAssertNil(ComponentLabelMatcher.match("", catalog: catalog))
    }

    func testRejectsPunctuationOnly() {
        XCTAssertNil(ComponentLabelMatcher.match("...", catalog: catalog))
    }

    func testRejectsTooDistant() {
        // Distance > 2 from any vocab word.
        XCTAssertNil(ComponentLabelMatcher.match("xyzqq", catalog: catalog))
    }

    // MARK: - Confidence

    func testExactAliasHasFullConfidence() {
        let match = ComponentLabelMatcher.match("btn", catalog: catalog)
        XCTAssertEqual(match?.confidence, 1.0)
    }

    func testTypoMatchHasReducedConfidence() {
        let match = ComponentLabelMatcher.match("buton", catalog: catalog)
        XCTAssertNotNil(match)
        XCTAssertLessThan(match?.confidence ?? 1.0, 1.0)
        XCTAssertGreaterThan(match?.confidence ?? 0.0, 0.0)
    }

    // MARK: - bestMatch

    func testBestMatchPicksHighestConfidence() {
        let candidates = ["xyz", "buton", "button"]
        let match = ComponentLabelMatcher.bestMatch(among: candidates, catalog: catalog)
        XCTAssertEqual(match?.componentName, "Button")
        XCTAssertEqual(match?.confidence, 1.0)
    }

    func testBestMatchReturnsNilWhenAllReject() {
        let candidates = ["xyz", "qqq", "foo"]
        XCTAssertNil(ComponentLabelMatcher.bestMatch(among: candidates, catalog: catalog))
    }

    func testRawTextPreserved() {
        let match = ComponentLabelMatcher.match("BUTTON!", catalog: catalog)
        XCTAssertEqual(match?.rawText, "BUTTON!")
    }
}
