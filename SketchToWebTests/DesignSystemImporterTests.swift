import XCTest
@testable import SketchToWeb

final class DesignSystemImporterTests: XCTestCase {

    // MARK: - GitHub

    func testGitHubRepoURLExpandsToRawCandidates() {
        let candidates = DesignSystemImporter.candidateRawURLs(for: "https://github.com/acme/brand")

        XCTAssertEqual(candidates.count, 4)
        XCTAssertEqual(
            candidates.first,
            "https://raw.githubusercontent.com/acme/brand/HEAD/DESIGN.md"
        )
        XCTAssertTrue(candidates.contains("https://raw.githubusercontent.com/acme/brand/HEAD/README.md"))
    }

    func testGitHubRepoURLStripsDotGit() {
        let candidates = DesignSystemImporter.candidateRawURLs(for: "https://github.com/acme/brand.git")
        XCTAssertEqual(
            candidates.first,
            "https://raw.githubusercontent.com/acme/brand/HEAD/DESIGN.md"
        )
    }

    // MARK: - GitLab

    func testGitLabRepoURLExpandsToRawCandidates() {
        let candidates = DesignSystemImporter.candidateRawURLs(for: "https://gitlab.com/acme/brand")

        XCTAssertEqual(
            candidates.first,
            "https://gitlab.com/acme/brand/-/raw/HEAD/DESIGN.md"
        )
    }

    // MARK: - Bitbucket

    func testBitbucketRepoURLExpandsToRawCandidates() {
        let candidates = DesignSystemImporter.candidateRawURLs(for: "https://bitbucket.org/acme/brand")

        XCTAssertEqual(
            candidates.first,
            "https://bitbucket.org/acme/brand/raw/HEAD/DESIGN.md"
        )
    }

    // MARK: - Raw URL passthrough

    func testRawGitHubUserContentURLIsPassedThrough() {
        let raw = "https://raw.githubusercontent.com/acme/brand/HEAD/CUSTOM.md"
        let candidates = DesignSystemImporter.candidateRawURLs(for: raw)
        XCTAssertEqual(candidates, [raw])
    }

    func testDirectMarkdownURLIsPassedThrough() {
        let raw = "https://example.com/internal/design.md"
        let candidates = DesignSystemImporter.candidateRawURLs(for: raw)
        XCTAssertEqual(candidates, [raw])
    }

    // MARK: - Unknown host

    func testUnknownHostFallsBackToProbingFilenames() {
        let candidates = DesignSystemImporter.candidateRawURLs(for: "https://design.acme.internal/brand")

        XCTAssertEqual(candidates.first, "https://design.acme.internal/brand")
        XCTAssertTrue(candidates.contains { $0.hasSuffix("DESIGN.md") })
        XCTAssertTrue(candidates.contains { $0.hasSuffix("README.md") })
    }

    // MARK: - Whitespace

    func testWhitespaceIsTrimmedBeforeProcessing() {
        let candidates = DesignSystemImporter.candidateRawURLs(for: "  https://github.com/acme/brand  ")
        XCTAssertEqual(
            candidates.first,
            "https://raw.githubusercontent.com/acme/brand/HEAD/DESIGN.md"
        )
    }
}
