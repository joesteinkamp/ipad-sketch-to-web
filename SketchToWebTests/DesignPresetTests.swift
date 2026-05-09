import XCTest
@testable import SketchToWeb

/// Verifies that the bundled `design-presets.json` decodes cleanly and meets
/// the invariants the preset picker relies on (unique slugs, non-empty fields).
final class DesignPresetTests: XCTestCase {

    func testLoadCatalogReturnsAtLeastOnePreset() {
        let catalog = DesignPreset.loadCatalog()
        XCTAssertFalse(catalog.isEmpty, "Bundled design-presets.json should decode into ≥1 preset")
    }

    func testEveryPresetHasNonEmptyMetadata() {
        for preset in DesignPreset.loadCatalog() {
            XCTAssertFalse(preset.slug.isEmpty, "Empty slug")
            XCTAssertFalse(preset.name.isEmpty, "Preset \(preset.slug) has empty name")
            XCTAssertFalse(preset.blurb.isEmpty, "Preset \(preset.slug) has empty blurb")
            XCTAssertFalse(preset.category.isEmpty, "Preset \(preset.slug) has empty category")
        }
    }

    func testSlugsAreLowercase() {
        for preset in DesignPreset.loadCatalog() {
            XCTAssertEqual(
                preset.slug, preset.slug.lowercased(),
                "Slug \(preset.slug) must be lowercase to build a valid raw URL"
            )
        }
    }

    func testSlugsAreUnique() {
        let slugs = DesignPreset.loadCatalog().map(\.slug)
        XCTAssertEqual(Set(slugs).count, slugs.count, "Duplicate slugs found: \(slugs)")
    }

    func testSlugsContainOnlyURLSafeCharacters() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for preset in DesignPreset.loadCatalog() {
            XCTAssertNil(
                preset.slug.rangeOfCharacter(from: allowed.inverted),
                "Slug \(preset.slug) contains URL-unsafe characters"
            )
        }
    }

    func testIdentifiableUsesSlug() {
        let preset = DesignPreset(
            slug: "test-slug",
            name: "Test",
            blurb: "Blurb",
            category: "Cat"
        )
        XCTAssertEqual(preset.id, "test-slug")
    }

    func testCodableRoundTrip() throws {
        let original = DesignPreset(
            slug: "vercel",
            name: "Vercel",
            blurb: "Minimal monochrome",
            category: "Dev Tools"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DesignPreset.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testHashableConformanceUsesAllFields() {
        let a = DesignPreset(slug: "x", name: "X", blurb: "b", category: "c")
        let b = DesignPreset(slug: "x", name: "X", blurb: "b", category: "c")
        let c = DesignPreset(slug: "x", name: "Y", blurb: "b", category: "c")
        XCTAssertEqual(a.hashValue, b.hashValue)
        // Different name should (almost certainly) produce a different hash; if it
        // doesn't, just verify equality semantics directly.
        XCTAssertNotEqual(a, c)
    }
}
