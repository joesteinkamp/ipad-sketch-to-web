import Foundation

/// A remote design tool that the app can hand off the generated sketch + code to
/// for native rendering as an editable design.
///
/// Each destination owns its MCP endpoint, OAuth configuration, and presentation
/// metadata. New destinations (Paper, Pencil, etc.) can be added as cases as they
/// expose remote MCP servers.
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

    // MARK: - OAuth

    /// OAuth endpoints and scope required to obtain a token for the destination's MCP.
    var oauthConfig: OAuthConfig {
        switch self {
        case .figma:
            return OAuthConfig(
                authorizeURL: URL(string: "https://www.figma.com/oauth")!,
                tokenURL: URL(string: "https://www.figma.com/api/oauth/token")!,
                clientID: AppConstants.figmaOAuthClientID,
                redirectURI: "sketchtoweb://oauth/figma",
                scopes: ["files:read", "file_content:read", "file_content:write"]
            )
        }
    }

    // MARK: - Keychain Keys

    /// Account identifiers used by `KeychainHelper` to namespace this destination's
    /// access token, refresh token, and expiry.
    var keychainKeys: KeychainKeys {
        switch self {
        case .figma:
            return KeychainKeys(
                accessToken: "figma-oauth-access",
                refreshToken: "figma-oauth-refresh",
                expiry: "figma-oauth-expiry"
            )
        }
    }

    // MARK: - Supporting Types

    struct OAuthConfig: Sendable {
        let authorizeURL: URL
        let tokenURL: URL
        let clientID: String
        let redirectURI: String
        let scopes: [String]
    }

    struct KeychainKeys: Sendable {
        let accessToken: String
        let refreshToken: String
        let expiry: String
    }
}
