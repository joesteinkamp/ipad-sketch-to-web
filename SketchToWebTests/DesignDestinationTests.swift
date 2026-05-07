import XCTest
@testable import SketchToWeb

final class DesignDestinationTests: XCTestCase {

    func testFigmaMCPEndpoint() {
        XCTAssertEqual(
            DesignDestination.figma.mcpEndpoint.absoluteString,
            "https://mcp.figma.com/mcp"
        )
    }

    func testFigmaOAuthConfig() {
        let config = DesignDestination.figma.oauthConfig
        XCTAssertEqual(config.authorizeURL.host, "www.figma.com")
        XCTAssertEqual(config.tokenURL.absoluteString, "https://www.figma.com/api/oauth/token")
        XCTAssertEqual(config.redirectURI, "sketchtoweb://oauth/figma")
        XCTAssertFalse(config.scopes.isEmpty)
    }

    func testFigmaKeychainKeysAreNamespaced() {
        let keys = DesignDestination.figma.keychainKeys
        XCTAssertTrue(keys.accessToken.contains("figma"))
        XCTAssertTrue(keys.refreshToken.contains("figma"))
        XCTAssertTrue(keys.expiry.contains("figma"))
        XCTAssertNotEqual(keys.accessToken, keys.refreshToken)
        XCTAssertNotEqual(keys.accessToken, keys.expiry)
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
