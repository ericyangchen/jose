import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            "Keychain operation failed (OSStatus \(status))"
        }
    }
}

/// Thin wrapper around Security's generic-password keychain items.
/// All José secrets share `service = "com.ericyangchen.jose"`, distinguished by `account`.
enum KeychainStore {
    static let service = "com.ericyangchen.jose"

    enum Account {
        static let openAIAPIKey = "openai_api_key"
    }

    static func save(_ value: String, for account: String) throws {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        default:
            throw KeychainError.unhandled(updateStatus)
        }
    }

    static func load(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    static func delete(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: Convenience for the API key

    static func loadAPIKey() -> String? {
        (try? load(for: Account.openAIAPIKey))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static func saveAPIKey(_ key: String) throws {
        try save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Account.openAIAPIKey)
    }

    static func deleteAPIKey() throws {
        try delete(for: Account.openAIAPIKey)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
