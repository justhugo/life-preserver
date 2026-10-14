import CryptoKit
import Foundation
import Security
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverProviders
#endif

/// One-time migration of the isolated session created by Life Preserver itself.
/// Never enumerate Keychain or consult the user's normal Codex/ChatGPT login.
@MainActor
enum LegacyOpenAISession {
    static func importOwned(account: UUID) throws -> SubscriptionCredential {
        let folder = AppStore.supportDirectory.appendingPathComponent("Connections/\(account.uuidString)")
        guard FileManager.default.fileExists(atPath: folder.path) else { throw SubscriptionError.authentication }
        let canonical = folder.resolvingSymlinksInPath().path
        let parent = AppStore.supportDirectory.appendingPathComponent("Connections").resolvingSymlinksInPath().path
        guard canonical == parent + "/" + account.uuidString else { throw SubscriptionError.authentication }
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Codex Auth", kSecAttrAccount as String: "cli|" + digest.prefix(16),
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else { throw SubscriptionError.authentication }
        let credential = try ProviderTokens.decode(JSONSerialization.data(withJSONObject: tokens), provider: .openai)
        try CredentialVault.save(credential, account: account)
        return credential
    }
}
