import XCTest
import SwiftData
@testable import SketchToWeb

@MainActor
final class DesignSystemTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        let schema = Schema([DesignSystem.self, Project.self, ProjectFolder.self, Generation.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - fetchOrCreate

    func testFetchOrCreateReturnsNewWhenEmpty() {
        let ds = DesignSystem.fetchOrCreate(in: container.mainContext)
        XCTAssertTrue(ds.companyBlurb.isEmpty)
        XCTAssertTrue(ds.isEmpty)

        let descriptor = FetchDescriptor<DesignSystem>()
        let all = try! container.mainContext.fetch(descriptor)
        XCTAssertEqual(all.count, 1)
    }

    func testFetchOrCreateReturnsExistingOnSubsequentCalls() {
        let first = DesignSystem.fetchOrCreate(in: container.mainContext)
        first.companyBlurb = "Acme"

        let second = DesignSystem.fetchOrCreate(in: container.mainContext)
        XCTAssertEqual(second.companyBlurb, "Acme")
        XCTAssertEqual(first.id, second.id)
    }

    // MARK: - isEmpty

    func testIsEmptyTrueForFreshlyInitialized() {
        let ds = DesignSystem()
        XCTAssertTrue(ds.isEmpty)
    }

    func testIsEmptyFalseWhenAnyFieldPopulated() {
        let ds = DesignSystem()
        ds.companyBlurb = "Acme"
        XCTAssertFalse(ds.isEmpty)

        let ds2 = DesignSystem()
        ds2.markdownContent = "# Doc"
        XCTAssertFalse(ds2.isEmpty)

        let ds3 = DesignSystem()
        ds3.fontFilePaths = ["/Fonts/Inter.ttf"]
        XCTAssertFalse(ds3.isEmpty)
    }

    // MARK: - Snapshot

    func testSnapshotMirrorsFieldsAndReducesPathsToFilenames() {
        let ds = DesignSystem(companyBlurb: "Acme", notes: "Use earth tones")
        ds.markdownContent = "# Brand"
        ds.markdownFilename = "DESIGN.md"
        ds.sourceURL = "https://github.com/acme/brand"
        ds.fontFilePaths = ["/var/mobile/.../Application Support/DesignSystem/Inter.ttf"]
        ds.assetFilePaths = ["/var/mobile/.../Application Support/DesignSystem/logo.svg"]

        let snap = ds.snapshot()

        XCTAssertEqual(snap.companyBlurb, "Acme")
        XCTAssertEqual(snap.notes, "Use earth tones")
        XCTAssertEqual(snap.markdownContent, "# Brand")
        XCTAssertEqual(snap.markdownFilename, "DESIGN.md")
        XCTAssertEqual(snap.sourceURL, "https://github.com/acme/brand")
        XCTAssertEqual(snap.fontFileNames, ["Inter.ttf"])
        XCTAssertEqual(snap.assetFileNames, ["logo.svg"])
    }

    func testSnapshotIsEmptyMatchesModel() {
        let empty = DesignSystem()
        XCTAssertTrue(empty.snapshot().isEmpty)

        let populated = DesignSystem(companyBlurb: "Acme")
        XCTAssertFalse(populated.snapshot().isEmpty)
    }
}
