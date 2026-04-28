import XCTest
@testable import SketchToWeb

final class PublicDesignSystemTests: XCTestCase {

    // MARK: - Catalog Loading

    func testCatalogLoadsFromBundle() throws {
        let catalog = try PublicDesignSystem.loadCatalog()
        XCTAssertFalse(catalog.isEmpty, "Bundled public-design-systems.json should not be empty")
    }

    func testCatalogContainsExactlyOneDefault() throws {
        let catalog = try PublicDesignSystem.loadCatalog()
        let defaults = catalog.filter { $0.isDefault }
        XCTAssertEqual(defaults.count, 1, "Exactly one catalog entry should be marked default")
    }

    func testNonDefaultEntriesHaveNonEmptyPromptFragment() throws {
        let catalog = try PublicDesignSystem.loadCatalog()
        let nonDefaults = catalog.filter { !$0.isDefault }
        XCTAssertFalse(nonDefaults.isEmpty)
        for entry in nonDefaults {
            XCTAssertFalse(
                entry.promptFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(entry.id) must have a non-empty promptFragment"
            )
        }
    }

    func testEntryLookupFallsBackToDefault() throws {
        let catalog = try PublicDesignSystem.loadCatalog()
        let resolved = PublicDesignSystem.entry(forID: "definitely-not-in-catalog", in: catalog)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.isDefault ?? false)
    }

    func testEntryLookupReturnsExactMatch() throws {
        let catalog = try PublicDesignSystem.loadCatalog()
        guard let target = catalog.first(where: { !$0.isDefault }) else {
            return XCTFail("Catalog has no non-default entry to test against")
        }
        let resolved = PublicDesignSystem.entry(forID: target.id, in: catalog)
        XCTAssertEqual(resolved?.id, target.id)
    }

    // MARK: - Display

    func testDisplayShortNameFallsBackToName() {
        let entry = PublicDesignSystem(
            id: "x",
            name: "Long Display Name",
            shortName: nil,
            description: "",
            isDefault: false,
            promptFragment: "fragment"
        )
        XCTAssertEqual(entry.displayShortName, "Long Display Name")
    }
}
