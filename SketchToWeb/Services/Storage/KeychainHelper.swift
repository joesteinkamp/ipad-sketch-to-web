import Foundation
import Security

/// A lightweight wrapper around the iOS Keychain Services API for storing
/// small blobs of sensitive data (e.g. API keys).
enum KeychainHelper {

    private static let serviceName = "com.sketchtoweb.gemini-apikey"

    // MARK: - Generic Operations

    /// Saves arbitrary data to the keychain under the given key.
    /// If an entry already exists for the key it will be updated in place.
    ///
    /// - Parameters:
    ///   - key: The account identifier.
    ///   - data: The data to store.
    @discardableResult
    static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        // Remove any existing item first.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads data from the keychain for the given key.
    ///
    /// - Parameter key: The account identifier.
    /// - Returns: The stored `Data`, or `nil` if not found.
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Deletes the keychain item for the given key.
    ///
    /// - Parameter key: The account identifier.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - API Key Convenience

    private static let apiKeyAccount = "gemini-api-key"

    /// Persists a Gemini API key in the keychain.
    ///
    /// - Parameter apiKey: The API key string.
    @discardableResult
    static func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }
        return save(key: apiKeyAccount, data: data)
    }

    /// Retrieves the stored Gemini API key, if any.
    ///
    /// - Returns: The API key string, or `nil` if not stored.
    static func loadAPIKey() -> String? {
        guard let data = load(key: apiKeyAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored Gemini API key from the keychain.
    @discardableResult
    static func deleteAPIKey() -> Bool {
        delete(key: apiKeyAccount)
    }

    // MARK: - String Convenience

    /// Persists a UTF-8 string under the given keychain key.
    @discardableResult
    static func saveString(_ value: String, key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    /// Loads a UTF-8 string from the keychain for the given key.
    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - OAuth Token Bundle

    /// A persisted OAuth token bundle (access + refresh + expiry) for a remote
    /// MCP destination. Stored as JSON under three keychain keys defined by the
    /// destination's `KeychainKeys` namespace.
    struct OAuthTokenBundle: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        /// Expiry as seconds since epoch.
        var expiresAt: TimeInterval?
    }

    /// Saves an OAuth token bundle for the given destination.
    @discardableResult
    static func saveOAuthTokens(_ bundle: OAuthTokenBundle, for destination: DesignDestination) -> Bool {
        let keys = destination.keychainKeys
        let accessOK = saveString(bundle.accessToken, key: keys.accessToken)
        let refreshOK: Bool
        if let refresh = bundle.refreshToken {
            refreshOK = saveString(refresh, key: keys.refreshToken)
        } else {
            delete(key: keys.refreshToken)
            refreshOK = true
        }
        let expiryOK: Bool
        if let expiresAt = bundle.expiresAt {
            expiryOK = saveString(String(expiresAt), key: keys.expiry)
        } else {
            delete(key: keys.expiry)
            expiryOK = true
        }
        return accessOK && refreshOK && expiryOK
    }

    /// Loads the OAuth token bundle for the given destination, if present.
    static func loadOAuthTokens(for destination: DesignDestination) -> OAuthTokenBundle? {
        let keys = destination.keychainKeys
        guard let access = loadString(key: keys.accessToken) else { return nil }
        let refresh = loadString(key: keys.refreshToken)
        let expiresAt = loadString(key: keys.expiry).flatMap(TimeInterval.init)
        return OAuthTokenBundle(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    /// Removes all OAuth tokens for the given destination.
    @discardableResult
    static func deleteOAuthTokens(for destination: DesignDestination) -> Bool {
        let keys = destination.keychainKeys
        let a = delete(key: keys.accessToken)
        let r = delete(key: keys.refreshToken)
        let e = delete(key: keys.expiry)
        return a && r && e
    }
}
