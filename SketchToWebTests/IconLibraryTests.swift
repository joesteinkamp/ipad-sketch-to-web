import XCTest
@testable import SketchToWeb

final class IconLibraryTests: XCTestCase {

    // MARK: - Metadata invariants

    func testEveryCaseHasDisplayNameBlurbAndPickerSymbol() {
        for library in IconLibrary.allCases {
            XCTAssertFalse(
                library.displayName.isEmpty,
                "\(library.rawValue) should have a non-empty display name."
            )
            XCTAssertFalse(
                library.blurb.isEmpty,
                "\(library.rawValue) should have a non-empty blurb."
            )
            XCTAssertFalse(
                library.pickerSymbol.isEmpty,
                "\(library.rawValue) should have an SF Symbol for the picker chip."
            )
            XCTAssertFalse(
                library.promptGuidance.isEmpty,
                "\(library.rawValue) must give the model some guidance, even '.none'."
            )
        }
    }

    func testRawValueRoundTrip() {
        for library in IconLibrary.allCases {
            let restored = IconLibrary(rawValue: library.rawValue)
            XCTAssertEqual(restored, library)
        }
    }

    func testIsNoneOnlyForNoneCase() {
        for library in IconLibrary.allCases {
            XCTAssertEqual(library.isNone, library == .none)
        }
    }

    // MARK: - Integration kinds

    func testCDNLibrariesEmitNonEmptyHeadTags() {
        // Libraries with a runtime must provide a `<script>` or `<link>` —
        // otherwise `HTMLTemplateEngine.injectIconLibrary` would inject nothing
        // and the markup would render blank.
        let cdnLibraries: [IconLibrary] = [.lucide, .phosphor, .materialSymbols]
        for library in cdnLibraries {
            XCTAssertFalse(
                library.headTags.isEmpty,
                "\(library.rawValue) is a CDN library and must emit headTags."
            )
            XCTAssertTrue(
                library.integrationKind == .cdnScript || library.integrationKind == .cdnStylesheet,
                "\(library.rawValue) should declare a CDN integration kind."
            )
        }
    }

    func testInlineSVGLibrariesEmitNoHeadTags() {
        // Heroicons and Carbon are inlined by the model; injecting CDN tags
        // would be wasted bandwidth.
        for library in [IconLibrary.heroicons, .carbon] {
            XCTAssertTrue(
                library.headTags.isEmpty,
                "\(library.rawValue) should not inject any head tags."
            )
            XCTAssertEqual(library.integrationKind, .inlineSVG)
            XCTAssertNil(library.initScript)
        }
    }

    func testNoneCaseInjectsNothing() {
        XCTAssertTrue(IconLibrary.none.headTags.isEmpty)
        XCTAssertNil(IconLibrary.none.initScript)
        XCTAssertEqual(IconLibrary.none.integrationKind, .none)
    }

    func testLucideHeadTagPointsAtUnpkg() {
        XCTAssertTrue(IconLibrary.lucide.headTags.contains("unpkg.com/lucide"))
    }

    func testPhosphorHeadTagPointsAtPhosphorWeb() {
        XCTAssertTrue(IconLibrary.phosphor.headTags.contains("@phosphor-icons/web"))
    }

    func testMaterialSymbolsHeadTagLoadsGoogleFonts() {
        XCTAssertTrue(IconLibrary.materialSymbols.headTags.contains("fonts.googleapis.com"))
        XCTAssertTrue(IconLibrary.materialSymbols.headTags.contains("Material+Symbols"))
    }

    func testLucideProvidesInitScriptThatCallsCreateIcons() {
        let script = IconLibrary.lucide.initScript
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("lucide.createIcons") ?? false)
    }

    // MARK: - Prompt guidance

    func testLucideGuidanceMentionsDataLucideAttribute() {
        XCTAssertTrue(IconLibrary.lucide.promptGuidance.contains("data-lucide"))
    }

    func testPhosphorGuidanceMentionsPhClassPrefix() {
        // Phosphor's web markup uses the `ph` class plus a `ph-<name>` modifier.
        XCTAssertTrue(IconLibrary.phosphor.promptGuidance.contains("ph "))
    }

    func testHeroiconsGuidanceMentionsStrokeCurrentColor() {
        XCTAssertTrue(IconLibrary.heroicons.promptGuidance.contains("currentColor"))
    }

    func testMaterialSymbolsGuidanceMentionsSpanClass() {
        XCTAssertTrue(
            IconLibrary.materialSymbols.promptGuidance.contains("material-symbols-outlined")
        )
    }

    func testCarbonGuidanceMentionsViewBox() {
        XCTAssertTrue(IconLibrary.carbon.promptGuidance.contains("viewBox"))
    }

    func testReactImportHintsResolveToCorrectPackages() {
        XCTAssertEqual(IconLibrary.none.reactImportHint, nil)
        XCTAssertTrue(IconLibrary.lucide.reactImportHint?.contains("lucide-react") ?? false)
        XCTAssertTrue(IconLibrary.phosphor.reactImportHint?.contains("@phosphor-icons/react") ?? false)
        XCTAssertTrue(IconLibrary.heroicons.reactImportHint?.contains("@heroicons/react") ?? false)
        XCTAssertTrue(IconLibrary.carbon.reactImportHint?.contains("@carbon/icons-react") ?? false)
        // Material Symbols intentionally has no React import hint — it's font-based.
        XCTAssertNil(IconLibrary.materialSymbols.reactImportHint)
    }
}
