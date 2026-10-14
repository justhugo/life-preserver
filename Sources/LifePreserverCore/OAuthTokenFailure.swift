import Foundation

/// Interpret only the OAuth error code; provider descriptions can contain private data.
public enum OAuthTokenFailure {
    public static func requiresReconnect(status: Int, data: Data) -> Bool {
        guard status == 400 || status == 401,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let code = json["error"] as? String ?? (json["error"] as? [String: Any])?["code"] as? String
        return ["invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"].contains(code ?? "")
    }
}
