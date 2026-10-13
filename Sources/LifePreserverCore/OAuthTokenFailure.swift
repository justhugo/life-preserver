import Foundation

/// Interpret only the OAuth error code; provider descriptions can contain private data.
public enum OAuthTokenFailure {
    public static func requiresReconnect(status: Int, data: Data) -> Bool {
        guard status == 400 || status == 401,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["error"] as? String == "invalid_grant"
    }
}
