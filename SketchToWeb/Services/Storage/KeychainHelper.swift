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
}
