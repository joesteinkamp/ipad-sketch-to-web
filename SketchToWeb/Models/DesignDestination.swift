import Foundation

/// A remote design tool that the app can hand off the generated sketch + code to
/// for native rendering as an editable design.
///
/// Each destination owns its MCP endpoint and presentation metadata. Authorization
/// is discovered at connect time via MCP's OAuth flow (RFC 9728 + RFC 7591 DCR),
/// so no developer-app credentials are baked in.
enum DesignDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case figma

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .figma:
            return "Figma"
        }
    }

    var systemImageName: String {
        switch self {
        case .figma:
            return "rectangle.connected.to.line.below"
        }
    }

    /// Whether this destination is currently shippable. Reserved cases (e.g. Paper
    /// when its MCP is local-only) can return `false` and be filtered from the UI.
    var isAvailable: Bool {
        switch self {
        case .figma:
            return true
        }
    }

    // MARK: - MCP

    /// The remote MCP endpoint for this destination.
    var mcpEndpoint: URL {
        switch self {
        case .figma:
            return URL(string: "https://mcp.figma.com/mcp")!
        }
    }

    /// Custom URL scheme used as the OAuth redirect. The scheme alone is enough
    /// for `ASWebAuthenticationSession` — no Info.plist registration required.
    var oauthRedirectURI: String {
        switch self {
        case .figma:
            return "sketchtoweb://oauth/figma"
        }
    }

    /// Human-readable client name advertised during Dynamic Client Registration.
    var oauthClientName: String {
        switch self {
        case .figma:
            return "Sketch to Web (iPad)"
        }
    }

    // MARK: - Keychain Keys

    /// Account identifiers used by `KeychainHelper` to namespace this destination's
    /// access token, refresh token, expiry, and DCR client registration.
    var keychainKeys: KeychainKeys {
        switch self {
        case .figma:
            return KeychainKeys(
                accessToken: "figma-oauth-access",
                refreshToken: "figma-oauth-refresh",
                expiry: "figma-oauth-expiry",
                registration: "figma-oauth-registration"
            )
        }
    }

    // MARK: - Supporting Types

    struct KeychainKeys: Sendable {
        let accessToken: String
        let refreshToken: String
        let expiry: String
        let registration: String
    }
}
