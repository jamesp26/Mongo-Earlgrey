import Foundation
import Security

/// Stores connection credentials in the macOS login Keychain so passwords are not persisted
/// in plaintext inside Application Support JSON files.
public enum KeychainStore {
    private static let service = "com.earlgrey.MongoEarlgrey.credentials"

    @discardableResult
    public static func savePassword(_ password: String, for connectionId: UUID) -> Bool {
        if password.isEmpty {
            deletePassword(for: connectionId)
            return true
        }

        let account = connectionId.uuidString
        guard let secretData = password.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributesToUpdate: [CFString: Any] = [
            kSecValueData: secretData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = secretData
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    public static func loadPassword(for connectionId: UUID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: connectionId.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    public static func deletePassword(for connectionId: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: connectionId.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
