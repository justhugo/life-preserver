import Foundation
import Security

// Diagnostics for Life Preserver's own Claude connection. Never print credentials or identity.
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@main struct CheckSubscription {
    static func main() async throws {
        guard [2, 3].contains(CommandLine.arguments.count), UUID(uuidString: CommandLine.arguments[1]) != nil else { return }
        let snapshot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Life Preserver/accounts.json")
        let accounts = try JSONSerialization.jsonObject(with: Data(contentsOf: snapshot)) as? [[String: Any]] ?? []
        guard accounts.contains(where: { ($0["id"] as? String) == CommandLine.arguments[1]
            && ($0["provider"] as? String) == "claude" }) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.lifepreserver.mac.subscriptions",
            kSecAttrAccount as String: CommandLine.arguments[1],
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        print("Keychain status:", status)
        guard status == errSecSuccess, let data = item as? Data,
              let credential = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let expiry = credential["expiresAt"] as? Double {
            let date = Date(timeIntervalSinceReferenceDate: expiry)
            print("Access expires:", ISO8601DateFormatter().string(from: date))
            print("Access expired:", date < Date())
        }
        print("Refresh credential present:", credential["refreshToken"] != nil)
        guard let access = credential["accessToken"] as? String else { return }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("LifePreserver/1.0", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        let (body, raw) = try await session.data(for: request)
        print("Usage HTTP:", (raw as? HTTPURLResponse)?.statusCode ?? 0)
        printError(body)
        guard CommandLine.arguments.last == "--refresh", let refresh = credential["refreshToken"] as? String else { return }
        var renewal = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        renewal.timeoutInterval = 20
        renewal.httpMethod = "POST"
        renewal.setValue("application/json", forHTTPHeaderField: "Content-Type")
        renewal.setValue("LifePreserver/1.0", forHTTPHeaderField: "User-Agent")
        renewal.httpBody = try JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token",
            "refresh_token": refresh, "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"])
        let (renewedBody, renewedRaw) = try await session.data(for: renewal)
        let code = (renewedRaw as? HTTPURLResponse)?.statusCode ?? 0
        print("Renewal HTTP:", code)
        printError(renewedBody)
        // A successful refresh can rotate the credential. Preserve it immediately.
        if (200..<300).contains(code),
           let result = try JSONSerialization.jsonObject(with: renewedBody) as? [String: Any],
           let token = result["access_token"] as? String {
            var updated = credential
            updated["accessToken"] = token
            updated["refreshToken"] = result["refresh_token"] ?? credential["refreshToken"]
            if let lifetime = result["expires_in"] as? Double {
                updated["expiresAt"] = Date().addingTimeInterval(lifetime).timeIntervalSinceReferenceDate
            }
            var updateQuery = query
            updateQuery.removeValue(forKey: kSecReturnData as String)
            updateQuery.removeValue(forKey: kSecMatchLimit as String)
            let saved = SecItemUpdate(updateQuery as CFDictionary,
                [kSecValueData as String: try JSONSerialization.data(withJSONObject: updated)] as CFDictionary)
            print("Rotated credential saved:", saved == errSecSuccess)
        }
    }
    static func printError(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let error = json["error"] as? [String: Any]
        let knownCodes = ["invalid_grant", "invalid_request", "authentication_error", "permission_error", "invalid_client", "invalid_scope"]
        if let code = (json["error"] as? String) ?? (error?["type"] as? String), knownCodes.contains(code) {
            print("Provider error:", code)
        }
        let description = (json["error_description"] as? String) ?? (error?["message"] as? String) ?? ""
        for marker in ["expired", "revoked", "invalid", "refresh", "scope", "malformed"] where description.lowercased().contains(marker) {
            print("Error mentions:", marker)
        }
    }
}
