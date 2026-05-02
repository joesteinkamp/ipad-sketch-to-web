import XCTest
@testable import SketchToWeb

final class DesignDestinationTests: XCTestCase {

    func testFigmaMCPEndpoint() {
        XCTAssertEqual(
            DesignDestination.figma.mcpEndpoint.absoluteString,
            "https://mcp.figma.com/mcp"
        )
    }

    func testFigmaOAuthRedirectAndClientName() {
        XCTAssertEqual(DesignDestination.figma.oauthRedirectURI, "sketchtoweb://oauth/figma")
        XCTAssertFalse(DesignDestination.figma.oauthClientName.isEmpty)
    }

    func testFigmaKeychainKeysAreNamespaced() {
        let keys = DesignDestination.figma.keychainKeys
        XCTAssertTrue(keys.accessToken.contains("figma"))
        XCTAssertTrue(keys.refreshToken.contains("figma"))
        XCTAssertTrue(keys.expiry.contains("figma"))
        XCTAssertTrue(keys.registration.contains("figma"))
        XCTAssertEqual(Set([keys.accessToken, keys.refreshToken, keys.expiry, keys.registration]).count, 4)
    }

    func testAllCasesIncludesFigma() {
        XCTAssertTrue(DesignDestination.allCases.contains(.figma))
    }

    func testFigmaIsAvailable() {
        XCTAssertTrue(DesignDestination.figma.isAvailable)
    }

    func testDisplayMetadata() {
        XCTAssertEqual(DesignDestination.figma.displayName, "Figma")
        XCTAssertFalse(DesignDestination.figma.systemImageName.isEmpty)
    }
}
