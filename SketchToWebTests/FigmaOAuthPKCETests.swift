import XCTest
import CryptoKit
@testable import SketchToWeb

/// Tests the pure PKCE generator used by `FigmaOAuth.connect()`. The OAuth flow
/// itself can't run headless (it needs `ASWebAuthenticationSession`), so we
/// verify only the cryptographic primitives.
final class FigmaOAuthPKCETests: XCTestCase {

    // MARK: - Verifier

    func testVerifierIsBase64URLEncoded() {
        let pkce = PKCE.generate()
        // RFC 7636 §4.1: base64-url alphabet = A-Z a-z 0-9 - _
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertNil(
            pkce.verifier.rangeOfCharacter(from: allowed.inverted),
            "Verifier contains characters outside base64-url alphabet"
        )
        XCTAssertFalse(pkce.verifier.contains("="), "Padding must be stripped")
        XCTAssertFalse(pkce.verifier.contains("+"), "Plus must become hyphen")
        XCTAssertFalse(pkce.verifier.contains("/"), "Slash must become underscore")
    }

    func testVerifierLengthIsWithinSpec() {
        // RFC 7636 §4.1: verifier is 43..=128 chars after encoding 32 random bytes.
        // base64(32 bytes) is 44 chars including 1 pad; trimmed to 43.
        let pkce = PKCE.generate()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertLessThanOrEqual(pkce.verifier.count, 128)
    }

    // MARK: - Challenge

    func testChallengeIsSHA256OfVerifierBase64URL() throws {
        let pkce = PKCE.generate()
        let expected = sha256Base64URL(pkce.verifier)
        XCTAssertEqual(pkce.challenge, expected, "Challenge must be base64url(SHA256(verifier))")
    }

    func testChallengeIsBase64URLEncoded() {
        let pkce = PKCE.generate()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertNil(pkce.challenge.rangeOfCharacter(from: allowed.inverted))
        XCTAssertFalse(pkce.challenge.contains("="))
    }

    func testChallengeIs43Chars() {
        // SHA-256 produces 32 bytes → 43 base64-url chars (no padding).
        let pkce = PKCE.generate()
        XCTAssertEqual(pkce.challenge.count, 43)
    }

    // MARK: - Uniqueness

    func testTwoGeneratesAreDistinct() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        XCTAssertNotEqual(a.verifier, b.verifier, "Verifier should be 256 bits of randomness")
        XCTAssertNotEqual(a.challenge, b.challenge)
    }

    func testManyGeneratesYieldUniqueVerifiers() {
        // 100 generates: collision probability is astronomical for 32 random bytes.
        let verifiers = (0..<100).map { _ in PKCE.generate().verifier }
        XCTAssertEqual(Set(verifiers).count, 100)
    }

    // MARK: - Helpers

    private func sha256Base64URL(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
