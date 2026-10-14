import CryptoKit
import Foundation
import Security

enum SharedSessionKeychain {
    private static let service = "com.lifepreserver.session-encryption.v1"
    private static var group: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LifePreserverKeychainAccessGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
    private static func query(_ account: String, sync: Bool) throws -> [String: Any] {
        guard let group else { throw SessionSharingError.keyPending }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecAttrAccessGroup as String: group,
                kSecAttrSynchronizable as String: sync, kSecUseDataProtectionKeychain as String: true]
    }
    static func key(owner: String, id: String, create: Bool = false) throws -> SymmetricKey {
        let account = "key|\(owner)|\(id)"
        if let bytes = try read(account, sync: true) {
            guard bytes.count == 32 else { throw SessionSharingError.invalidSession }
            return SymmetricKey(data: bytes)
        }
        guard create else { throw SessionSharingError.keyPending }
        let key = SymmetricKey(size: .bits256)
        try write(key.withUnsafeBytes { Data($0) }, account: account, sync: true)
        return key
    }
    static func read(_ account: String, sync: Bool) throws -> Data? {
        var query = try query(account, sync: sync)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data else { throw SessionSharingError.keyPending }
        return bytes
    }
    static func write(_ data: Data, account: String, sync: Bool) throws {
        let query = try query(account, sync: sync)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SessionSharingError.keyPending }
        } else if status != errSecSuccess { throw SessionSharingError.keyPending }
    }
    static func remove(_ account: String, sync: Bool) throws {
        let status = SecItemDelete(try query(account, sync: sync) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SessionSharingError.keyPending }
    }
}
