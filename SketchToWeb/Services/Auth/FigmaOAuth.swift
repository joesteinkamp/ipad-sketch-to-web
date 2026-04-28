import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// OAuth 2.0 + PKCE (S256) flow for connecting to Figma's account, used to obtain
/// the bearer token that authorizes calls to the Figma remote MCP server at
/// https://mcp.figma.com/mcp.
///
/// Tokens are persisted via `KeychainHelper.saveOAuthTokens(_:for:)`. Callers
/// should use `currentAccessToken()` which transparently refreshes when expired.
@MainActor
final class FigmaOAuth: NSObject {

    static let shared = FigmaOAuth()

    private let destination: DesignDestination = .figma
    private var session: ASWebAuthenticationSession?

    // MARK: - Errors

    enum OAuthError: LocalizedError {
        case missingClientID
        case userCancelled
        case invalidCallback
        case missingCode
        case missingAccessToken
        case noStoredToken
        case refreshFailed(String)
        case network(Error)
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingClientID:
                return "Figma OAuth is not configured. Set FIGMA_OAUTH_CLIENT_ID in the app's Info.plist."
            case .userCancelled:
                return "Figma sign-in was cancelled."
            case .invalidCallback:
                return "Figma returned an invalid callback URL."
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

    /// Starts the browser-based OAuth flow, persists the resulting tokens, and
    /// returns the access token on success.
    @discardableResult
    func connect() async throws -> String {
        let config = destination.oauthConfig
        guard config.clientID != "REPLACE_WITH_FIGMA_CLIENT_ID", !config.clientID.isEmpty else {
            throw OAuthError.missingClientID
        }

        let pkce = PKCE.generate()
        let state = UUID().uuidString

        let authURL = try buildAuthorizeURL(config: config, pkce: pkce, state: state)
        let callbackScheme = scheme(from: config.redirectURI)
        let callbackURL = try await presentAuthSession(authURL: authURL, callbackScheme: callbackScheme)

        let code = try extractAuthorizationCode(from: callbackURL, expectedState: state)
        let bundle = try await exchangeCodeForToken(code: code, pkce: pkce, config: config)
        KeychainHelper.saveOAuthTokens(bundle, for: destination)
        return bundle.accessToken
    }

    /// Clears stored tokens and signs the user out locally.
    func disconnect() {
        KeychainHelper.deleteOAuthTokens(for: destination)
    }

    /// Returns a valid access token, refreshing it if expired. Throws
    /// `OAuthError.noStoredToken` if the user has not connected.
    func currentAccessToken() async throws -> String {
        guard let bundle = KeychainHelper.loadOAuthTokens(for: destination) else {
            throw OAuthError.noStoredToken
        }
        if isExpired(bundle) {
            return try await refresh(bundle: bundle)
        }
        return bundle.accessToken
    }

    // MARK: - Refresh

    private func isExpired(_ bundle: KeychainHelper.OAuthTokenBundle) -> Bool {
        guard let expiresAt = bundle.expiresAt else { return false }
        // Refresh 60s early to avoid races.
        return Date().timeIntervalSince1970 >= (expiresAt - 60)
    }

    private func refresh(bundle: KeychainHelper.OAuthTokenBundle) async throws -> String {
        guard let refreshToken = bundle.refreshToken else {
            throw OAuthError.refreshFailed("No refresh token available; please reconnect.")
        }
        let config = destination.oauthConfig

        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID
        ]
        request.httpBody = encodeForm(params).data(using: .utf8)

        let new = try await postTokenRequest(request)
        // Carry over the existing refresh token if Figma omits it on refresh.
        let merged = KeychainHelper.OAuthTokenBundle(
            accessToken: new.accessToken,
            refreshToken: new.refreshToken ?? bundle.refreshToken,
            expiresAt: new.expiresAt
        )
        KeychainHelper.saveOAuthTokens(merged, for: destination)
        return merged.accessToken
    }

    // MARK: - Authorization URL

    private func buildAuthorizeURL(
        config: DesignDestination.OAuthConfig,
        pkce: PKCE,
        state: String
    ) throws -> URL {
        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw OAuthError.invalidCallback }
        return url
    }

    private func scheme(from redirectURI: String) -> String {
        URL(string: redirectURI)?.scheme ?? "sketchtoweb"
    }

    // MARK: - Web Auth Session

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

    // MARK: - Code Extraction

    private func extractAuthorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw OAuthError.invalidCallback
        }
        if let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
           returnedState != expectedState {
            throw OAuthError.invalidCallback
        }
        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            throw OAuthError.server(0, errorParam)
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        return code
    }

    // MARK: - Token Exchange

    private func exchangeCodeForToken(
        code: String,
        pkce: PKCE,
        config: DesignDestination.OAuthConfig
    ) async throws -> KeychainHelper.OAuthTokenBundle {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "code_verifier": pkce.verifier
        ]
        request.httpBody = encodeForm(params).data(using: .utf8)
        return try await postTokenRequest(request)
    }

    private func postTokenRequest(_ request: URLRequest) async throws -> KeychainHelper.OAuthTokenBundle {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.network(error)
        }

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

    private func encodeForm(_ params: [String: String]) -> String {
        params
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }
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
