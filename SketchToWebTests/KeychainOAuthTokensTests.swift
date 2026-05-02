import XCTest
@testable import SketchToWeb

final class KeychainOAuthTokensTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        KeychainHelper.deleteOAuthTokens(for: .figma)
    }

    func testRoundTripPersistsAccessRefreshAndExpiry() {
        let bundle = KeychainHelper.OAuthTokenBundle(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresAt: 1_900_000_000
        )
        XCTAssertTrue(KeychainHelper.saveOAuthTokens(bundle, for: .figma))

        let loaded = KeychainHelper.loadOAuthTokens(for: .figma)
        XCTAssertEqual(loaded?.accessToken, "access-123")
        XCTAssertEqual(loaded?.refreshToken, "refresh-456")
        XCTAssertEqual(loaded?.expiresAt, 1_900_000_000)
    }

    func testDeleteRemovesAllFields() {
        let bundle = KeychainHelper.OAuthTokenBundle(
            accessToken: "x",
            refreshToken: "y",
            expiresAt: 100
        )
        KeychainHelper.saveOAuthTokens(bundle, for: .figma)
        KeychainHelper.deleteOAuthTokens(for: .figma)

        XCTAssertNil(KeychainHelper.loadOAuthTokens(for: .figma))
    }

    func testRefreshTokenIsClearedWhenSavedAsNil() {
        let initial = KeychainHelper.OAuthTokenBundle(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: 100
        )
        KeychainHelper.saveOAuthTokens(initial, for: .figma)

        let updated = KeychainHelper.OAuthTokenBundle(
            accessToken: "a2",
            refreshToken: nil,
            expiresAt: 200
        )
        KeychainHelper.saveOAuthTokens(updated, for: .figma)

        let loaded = KeychainHelper.loadOAuthTokens(for: .figma)
        XCTAssertEqual(loaded?.accessToken, "a2")
        XCTAssertNil(loaded?.refreshToken)
        XCTAssertEqual(loaded?.expiresAt, 200)
    }

    func testLoadReturnsNilWhenNothingStored() {
        KeychainHelper.deleteOAuthTokens(for: .figma)
        XCTAssertNil(KeychainHelper.loadOAuthTokens(for: .figma))
    }
}
