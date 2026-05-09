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

    func testSnapshotMirrorsSynthesisFields() {
        let ds = DesignSystem(companyBlurb: "Acme")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ds.synthesizedMarkdown = "## Brand Voice\nWarm."
        ds.synthesizedAt = now

        let snap = ds.snapshot()
        XCTAssertEqual(snap.synthesizedMarkdown, "## Brand Voice\nWarm.")
        XCTAssertEqual(snap.synthesizedAt, now)
    }

    // MARK: - Fingerprint

    func testFingerprintIsStableAcrossIdenticalInputs() {
        let ds1 = DesignSystem(companyBlurb: "Acme", notes: "earth tones")
        ds1.sourceURL = "https://github.com/acme/brand"
        ds1.sourceURLContent = "# Brand"
        ds1.fontFilePaths = ["/path/Inter.ttf", "/path/Display.otf"]

        let ds2 = DesignSystem(companyBlurb: "Acme", notes: "earth tones")
        ds2.sourceURL = "https://github.com/acme/brand"
        ds2.sourceURLContent = "# Brand"
        ds2.fontFilePaths = ["/path/Inter.ttf", "/path/Display.otf"]

        XCTAssertEqual(ds1.currentInputFingerprint, ds2.currentInputFingerprint)
    }

    func testFingerprintIgnoresFontPathDirectoryAndOrder() {
        let ds1 = DesignSystem()
        ds1.fontFilePaths = ["/foo/Inter.ttf", "/bar/Display.otf"]

        let ds2 = DesignSystem()
        // Different directories, different order — fingerprint compares
        // sorted basenames so both should match.
        ds2.fontFilePaths = ["/Library/Display.otf", "/elsewhere/Inter.ttf"]

        XCTAssertEqual(ds1.currentInputFingerprint, ds2.currentInputFingerprint)
    }

    func testFingerprintChangesWhenAnyTrackedFieldChanges() {
        let baseline: () -> DesignSystem = {
            let ds = DesignSystem(companyBlurb: "Acme", notes: "earthy")
            ds.markdownContent = "# Doc"
            ds.sourceURL = "https://github.com/acme/brand"
            ds.sourceURLContent = "fetched"
            ds.zipFilename = "design.zip"
            ds.zipExtractedContent = "tailwind config"
            ds.fontFilePaths = ["/path/Inter.ttf"]
            ds.assetFilePaths = ["/path/logo.svg"]
            return ds
        }
        let original = baseline().currentInputFingerprint

        let mutators: [(String, (DesignSystem) -> Void)] = [
            ("companyBlurb", { $0.companyBlurb = "Acme!" }),
            ("notes", { $0.notes = "different" }),
            ("markdownContent", { $0.markdownContent = "# New" }),
            ("sourceURL", { $0.sourceURL = "https://other.example" }),
            ("sourceURLContent", { $0.sourceURLContent = "different" }),
            ("zipFilename", { $0.zipFilename = "other.zip" }),
            ("zipExtractedContent", { $0.zipExtractedContent = "different" }),
            ("fontFilePaths", { $0.fontFilePaths = ["/path/Other.ttf"] }),
            ("assetFilePaths", { $0.assetFilePaths = ["/path/mark.svg"] })
        ]

        for (label, mutate) in mutators {
            let ds = baseline()
            mutate(ds)
            XCTAssertNotEqual(
                ds.currentInputFingerprint,
                original,
                "fingerprint should change when \(label) changes"
            )
        }
    }

    // MARK: - Staleness

    func testIsSynthesisStaleFalseWhenNoSynthesisExists() {
        let ds = DesignSystem(companyBlurb: "Acme")
        XCTAssertFalse(ds.isSynthesisStale)
    }

    func testIsSynthesisStaleFalseWhenFingerprintMatches() {
        let ds = DesignSystem(companyBlurb: "Acme")
        ds.synthesizedMarkdown = "## Brand"
        ds.synthesizedInputFingerprint = ds.currentInputFingerprint
        XCTAssertFalse(ds.isSynthesisStale)
    }

    func testIsSynthesisStaleTrueAfterInputChange() {
        let ds = DesignSystem(companyBlurb: "Acme")
        ds.synthesizedMarkdown = "## Brand"
        ds.synthesizedInputFingerprint = ds.currentInputFingerprint

        ds.companyBlurb = "Acme — playful fintech"
        XCTAssertTrue(ds.isSynthesisStale)
    }

    func testIsSynthesisStaleFalseWhenSynthesizedMarkdownIsEmptyString() {
        let ds = DesignSystem(companyBlurb: "Acme")
        ds.synthesizedMarkdown = ""
        ds.synthesizedInputFingerprint = "stale-fingerprint"
        XCTAssertFalse(ds.isSynthesisStale)
    }
}
