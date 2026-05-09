import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// MCP-style OAuth client for Figma's remote MCP server at
/// `https://mcp.figma.com/mcp`. Uses the standard MCP authorization flow:
///
/// 1. **Discovery** (RFC 9728) — fetch protected-resource metadata, then the
///    authorization server's metadata (RFC 8414), to learn the authorize / token
///    / registration endpoints.
/// 2. **Dynamic Client Registration** (RFC 7591) — register this app as a public
///    client at runtime; no developer-app credentials are baked in.
/// 3. **Authorization Code + PKCE** — present an `ASWebAuthenticationSession`
///    sheet so the user signs in to Figma in a browser, then exchange the code
///    for an access + refresh token.
///
/// Tokens land in the Keychain via `KeychainHelper.saveOAuthTokens(_:for:)` and
/// the discovery + registration result via
/// `KeychainHelper.saveOAuthRegistration(_:for:)`. Callers should use
/// `currentAccessToken()`, which transparently refreshes when expired.
@MainActor
final class FigmaOAuth: NSObject {

    static let shared = FigmaOAuth()

    private let destination: DesignDestination = .figma
    private var session: ASWebAuthenticationSession?

    // MARK: - Errors

    enum OAuthError: LocalizedError {
        case discoveryFailed(String)
        case registrationFailed(String)
        case userCancelled
        case invalidCallback
        case stateMismatch
        case missingCode
        case missingAccessToken
        case noStoredToken
        case refreshFailed(String)
        case network(Error)
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .discoveryFailed(let message):
                return "Could not discover Figma's OAuth server: \(message)"
            case .registrationFailed(let message):
                return "Could not register the app with Figma: \(message)"
            case .userCancelled:
                return "Figma sign-in was cancelled."
            case .invalidCallback:
                return "Figma returned an invalid callback URL."
            case .stateMismatch:
                return "OAuth state did not match — aborting for safety."
            case .missingCode:
                return "Figma did not return an authorization code."
            case .missingAccessToken:
                return "Figma did not return an access token."
            case .noStoredToken:
                return "Not signed in to Figma. Connect in Settings."
            case .refreshFailed(let message):
                return "Failed to refresh Figma session: \(message)"
            case .network(let error):
                return "Network error talking to Figma: \(error.localizedDescription)"
            case .server(let status, let message):
                return "Figma OAuth error (\(status)): \(message)"
            }
        }
    }

    // MARK: - Public API

    /// Whether the user currently has a stored Figma token (may still be expired).
    var isConnected: Bool {
        KeychainHelper.loadOAuthTokens(for: destination) != nil
    }

    /// Runs discovery + DCR (if needed) + the browser-based authorization flow,
    /// persists the resulting tokens, and returns the access token.
    @discardableResult
    func connect() async throws -> String {
        let registration = try await ensureClientRegistered()
        let pkce = PKCE.generate()
        let state = UUID().uuidString

        let authURL = try buildAuthorizeURL(registration: registration, pkce: pkce, state: state)
        let scheme = oauthCallbackScheme()
        let callbackURL = try await presentAuthSession(authURL: authURL, callbackScheme: scheme)
        let code = try extractAuthorizationCode(from: callbackURL, expectedState: state)

        let bundle = try await exchangeCodeForToken(code: code, pkce: pkce, registration: registration)
        KeychainHelper.saveOAuthTokens(bundle, for: destination)
        return bundle.accessToken
    }

    /// Clears stored tokens and the client registration, signing the user out
    /// locally. The next `connect()` will re-run discovery + DCR.
    func disconnect() {
        KeychainHelper.deleteOAuthTokens(for: destination)
        KeychainHelper.deleteOAuthRegistration(for: destination)
    }

    /// Returns a valid access token, refreshing it if expired. Throws
    /// `OAuthError.noStoredToken` if the user hasn't connected.
    func currentAccessToken() async throws -> String {
        guard let bundle = KeychainHelper.loadOAuthTokens(for: destination) else {
            throw OAuthError.noStoredToken
        }
        if isExpired(bundle) {
            return try await refresh(bundle: bundle)
        }
        return bundle.accessToken
    }

    // MARK: - Discovery + DCR

    private func ensureClientRegistered() async throws -> KeychainHelper.OAuthClientRegistration {
        if let cached = KeychainHelper.loadOAuthRegistration(for: destination) {
            return cached
        }

        let metadata = try await discoverAuthorizationServer()
        let clientID = try await registerClient(metadata: metadata)

        let registration = KeychainHelper.OAuthClientRegistration(
            clientID: clientID,
            authorizationEndpoint: metadata.authorizationEndpoint,
            tokenEndpoint: metadata.tokenEndpoint,
            registrationEndpoint: metadata.registrationEndpoint,
            resource: metadata.resource,
            supportedScopes: metadata.scopesSupported
        )
        KeychainHelper.saveOAuthRegistration(registration, for: destination)
        return registration
    }

    /// Resolves the authorization server starting from the MCP endpoint.
    /// Tries protected-resource metadata first (RFC 9728), then falls back to
    /// treating the MCP origin as its own authorization server.
    private func discoverAuthorizationServer() async throws -> AuthorizationServerMetadata {
        let mcp = destination.mcpEndpoint

        var authServerURL: URL?
        var resource: URL?

        if let prm = try? await fetchProtectedResourceMetadata(mcp: mcp) {
            resource = prm.resource ?? mcp
            authServerURL = prm.authorizationServers.first
        }

        let asBase = authServerURL ?? originURL(of: mcp)

        let asMetadata = try await fetchAuthorizationServerMetadata(base: asBase)
        return AuthorizationServerMetadata(
            authorizationEndpoint: asMetadata.authorizationEndpoint,
            tokenEndpoint: asMetadata.tokenEndpoint,
            registrationEndpoint: asMetadata.registrationEndpoint,
            scopesSupported: asMetadata.scopesSupported,
            resource: resource ?? mcp
        )
    }

    private func fetchProtectedResourceMetadata(mcp: URL) async throws -> ProtectedResourceMetadata {
        var components = URLComponents(url: mcp, resolvingAgainstBaseURL: false)!
        components.path = "/.well-known/oauth-protected-resource"
        components.query = nil
        guard let url = components.url else {
            throw OAuthError.discoveryFailed("Could not derive PRM URL")
        }
        let json = try await getJSON(from: url)
        let resourceString = json["resource"] as? String
        let servers = (json["authorization_servers"] as? [String]) ?? []
        let serverURLs = servers.compactMap(URL.init(string:))
        return ProtectedResourceMetadata(
            resource: resourceString.flatMap(URL.init(string:)),
            authorizationServers: serverURLs
        )
    }

    private func fetchAuthorizationServerMetadata(base: URL) async throws -> AuthorizationServerWireMetadata {
        // RFC 8414 well-known location, with OpenID Connect Discovery as fallback.
        let candidates = [
            base.appendingPathComponent(".well-known/oauth-authorization-server"),
            base.appendingPathComponent(".well-known/openid-configuration")
        ]
        var lastError: Error?
        for url in candidates {
            do {
                let json = try await getJSON(from: url)
                guard
                    let authStr = json["authorization_endpoint"] as? String,
                    let tokenStr = json["token_endpoint"] as? String,
                    let authURL = URL(string: authStr),
                    let tokenURL = URL(string: tokenStr)
                else { continue }
                let regURL = (json["registration_endpoint"] as? String).flatMap(URL.init(string:))
                let scopes = (json["scopes_supported"] as? [String]) ?? []
                return AuthorizationServerWireMetadata(
                    authorizationEndpoint: authURL,
                    tokenEndpoint: tokenURL,
                    registrationEndpoint: regURL,
                    scopesSupported: scopes
                )
            } catch {
                lastError = error
                continue
            }
        }
        throw OAuthError.discoveryFailed(
            (lastError as? LocalizedError)?.errorDescription ?? "No metadata at \(base)"
        )
    }

    private func registerClient(metadata: AuthorizationServerMetadata) async throws -> String {
        guard let regURL = metadata.registrationEndpoint else {
            throw OAuthError.registrationFailed(
                "Authorization server does not support Dynamic Client Registration."
            )
        }

        let body: [String: Any] = [
            "client_name": destination.oauthClientName,
            "redirect_uris": [destination.oauthRedirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "application_type": "native"
        ]

        var request = URLRequest(url: regURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await dataRequest(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw OAuthError.registrationFailed("HTTP \(status): \(detail)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientID = json["client_id"] as? String else {
            throw OAuthError.registrationFailed("Registration response missing client_id")
        }
        return clientID
    }

    // MARK: - Authorization

    private func buildAuthorizeURL(
        registration: KeychainHelper.OAuthClientRegistration,
        pkce: PKCE,
        state: String
    ) throws -> URL {
        var components = URLComponents(url: registration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: registration.clientID),
            URLQueryItem(name: "redirect_uri", value: destination.oauthRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if !registration.supportedScopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: registration.supportedScopes.joined(separator: " ")))
        }
        if let resource = registration.resource {
            items.append(URLQueryItem(name: "resource", value: resource.absoluteString))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw OAuthError.invalidCallback }
        return url
    }

    private func oauthCallbackScheme() -> String {
        URL(string: destination.oauthRedirectURI)?.scheme ?? "sketchtoweb"
    }

    private func presentAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.userCancelled)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: OAuthError.network(error))
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.invalidCallback)
            }
        }
    }

    private func extractAuthorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw OAuthError.invalidCallback
        }
        if let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
           returnedState != expectedState {
            throw OAuthError.stateMismatch
        }
        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value
            throw OAuthError.server(0, description ?? errorParam)
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        return code
    }

    // MARK: - Token Exchange + Refresh

    private func exchangeCodeForToken(
        code: String,
        pkce: PKCE,
        registration: KeychainHelper.OAuthClientRegistration
    ) async throws -> KeychainHelper.OAuthTokenBundle {
        var params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": registration.clientID,
            "redirect_uri": destination.oauthRedirectURI,
            "code_verifier": pkce.verifier
        ]
        if let resource = registration.resource {
            params["resource"] = resource.absoluteString
        }

        let request = formURLEncodedPOST(url: registration.tokenEndpoint, params: params)
        return try await postTokenRequest(request)
    }

    private func refresh(bundle: KeychainHelper.OAuthTokenBundle) async throws -> String {
        guard let registration = KeychainHelper.loadOAuthRegistration(for: destination) else {
            throw OAuthError.refreshFailed("Lost client registration; please reconnect.")
        }
        guard let refreshToken = bundle.refreshToken else {
            throw OAuthError.refreshFailed("No refresh token available; please reconnect.")
        }

        var params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": registration.clientID
        ]
        if let resource = registration.resource {
            params["resource"] = resource.absoluteString
        }

        let request = formURLEncodedPOST(url: registration.tokenEndpoint, params: params)
        let new = try await postTokenRequest(request)
        let merged = KeychainHelper.OAuthTokenBundle(
            accessToken: new.accessToken,
            refreshToken: new.refreshToken ?? bundle.refreshToken,
            expiresAt: new.expiresAt
        )
        KeychainHelper.saveOAuthTokens(merged, for: destination)
        return merged.accessToken
    }

    private func postTokenRequest(_ request: URLRequest) async throws -> KeychainHelper.OAuthTokenBundle {
        let (data, response) = try await dataRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.server(-1, "Invalid HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OAuthError.server(http.statusCode, message)
        }
        return try parseTokenResponse(data)
    }

    private func parseTokenResponse(_ data: Data) throws -> KeychainHelper.OAuthTokenBundle {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.server(0, "Token response is not JSON")
        }
        guard let access = json["access_token"] as? String else {
            throw OAuthError.missingAccessToken
        }
        let refresh = json["refresh_token"] as? String
        let expiresAt: TimeInterval?
        if let expiresIn = json["expires_in"] as? TimeInterval {
            expiresAt = Date().timeIntervalSince1970 + expiresIn
        } else if let expiresIn = json["expires_in"] as? Int {
            expiresAt = Date().timeIntervalSince1970 + TimeInterval(expiresIn)
        } else {
            expiresAt = nil
        }
        return KeychainHelper.OAuthTokenBundle(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt
        )
    }

    // MARK: - Helpers

    private func isExpired(_ bundle: KeychainHelper.OAuthTokenBundle) -> Bool {
        guard let expiresAt = bundle.expiresAt else { return false }
        // Refresh 60s early to avoid races.
        return Date().timeIntervalSince1970 >= (expiresAt - 60)
    }

    private func originURL(of url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        return components.url ?? url
    }

    private func dataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.network(error)
        }
    }

    private func getJSON(from url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await dataRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.discoveryFailed("Invalid response from \(url)")
        }
        guard (200...299).contains(http.statusCode) else {
            throw OAuthError.discoveryFailed("HTTP \(http.statusCode) from \(url)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.discoveryFailed("Body from \(url) is not JSON")
        }
        return json
    }

    private func formURLEncodedPOST(url: URL, params: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        return request
    }
}

// MARK: - Discovery types

private struct ProtectedResourceMetadata {
    let resource: URL?
    let authorizationServers: [URL]
}

private struct AuthorizationServerWireMetadata {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let scopesSupported: [String]
}

private struct AuthorizationServerMetadata {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let scopesSupported: [String]
    let resource: URL?
}

// MARK: - PKCE

/// PKCE challenge/verifier pair (RFC 7636, S256).
struct PKCE: Sendable {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncodedString()

        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

private extension Data {
    /// Base64-URL encoding without padding (RFC 7636 §4.1).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Presentation Anchor

extension FigmaOAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession invokes this on the main thread.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            for scene in scenes {
                guard let windowScene = scene as? UIWindowScene,
                      windowScene.activationState == .foregroundActive else { continue }
                if let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    return window
                }
                if let window = windowScene.windows.first {
                    return window
                }
            }
            return ASPresentationAnchor()
        }
    }
}
