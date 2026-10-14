import Foundation
import Security

#if SWIFT_PACKAGE
import LifePreserverCore
#endif

enum CredentialVault {
    private static let service = "com.lifepreserver.mac.subscriptions"
    static func save(_ credential: SubscriptionCredential, account: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account.uuidString]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw VaultError.status(result) }
        } else if status != errSecSuccess { throw VaultError.status(status) }
    }
    static func read(account: UUID) throws -> SubscriptionCredential {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account.uuidString,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw VaultError.status(status) }
        return try JSONDecoder().decode(SubscriptionCredential.self, from: data)
    }
    static func remove(account: UUID) throws {
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account.uuidString] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw VaultError.status(result) }
    }
    enum VaultError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? { "Your credentials couldn’t be accessed in Keychain. Unlock your Mac and try reconnecting." }
    }
}
