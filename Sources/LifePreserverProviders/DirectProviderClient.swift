import Foundation
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

public struct SubscriptionOAuthConfiguration {
    public let provider: Provider
    public init(provider: Provider) { self.provider = provider }
    public var clientID: String {
        switch provider {
        case .openai: return "app_EMoamEEZ73f0CkXaXp7hrann"
        case .claude: return "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        case .grok: return "b1a00492-073a-47ea-816f-4c329264a828"
        case .grokBot: return "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
        }
    }
    public var authorizeURL: URL {
        URL(string: provider == .openai ? "https://auth.openai.com/oauth/authorize"
            : provider == .claude ? "https://claude.ai/oauth/authorize" : "https://auth.x.ai/oauth2/authorize")!
    }
    public var tokenURL: URL {
        URL(string: provider == .openai ? "https://auth.openai.com/oauth/token"
            : provider == .claude ? "https://platform.claude.com/v1/oauth/token"
            : provider == .grokBot ? "https://api2.cursor.sh/oauth/token" : "https://auth.x.ai/oauth2/token")!
    }
    public var scope: String {
        provider == .openai ? "openid profile email offline_access"
            : provider == .claude ? "user:profile" : "openid profile email offline_access grok-cli:access api:access"
    }
}

/// Claims supply identity/expiry hints only. The provider validates the bearer token.
public enum ProviderTokens {
    public static func claims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3, parts[1].count < 65_536 else { return [:] }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
    public static func decode(_ data: Data, provider: Provider, camelCase: Bool = false, at now: Date = Date()) throws -> SubscriptionCredential {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let access = json[camelCase ? "accessToken" : "access_token"] as? String, !access.isEmpty else { throw SubscriptionError.authentication }
        let identity = claims(json["id_token"] as? String ?? access)
        let accessClaims = claims(access)
        let auth = identity["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        let account = json["account"] as? [String: Any]
        return SubscriptionCredential(accessToken: access, refreshToken: json[camelCase ? "refreshToken" : "refresh_token"] as? String,
            expiresAt: (json["expires_in"] as? Double).map { now.addingTimeInterval($0) }
                ?? (accessClaims["exp"] as? Double).map { Date(timeIntervalSince1970: $0) },
            email: account?["email_address"] as? String ?? identity["email"] as? String,
            plan: (auth["chatgpt_plan_type"] as? String)?.capitalized,
            providerAccountID: json["account_id"] as? String ?? auth["chatgpt_account_id"] as? String)
    }
}

@MainActor
public enum DirectProviderClient {
    public static func exchange(_ fields: [String: String], provider: Provider) async throws -> SubscriptionCredential {
        let config = SubscriptionOAuthConfiguration(provider: provider)
        let data: Data
        if provider == .grok || (provider == .openai && fields["grant_type"] == "authorization_code") {
            var form = URLComponents()
            form.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            data = try await SubscriptionHTTP.shared.request(config.tokenURL,
                body: Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8),
                contentType: "application/x-www-form-urlencoded", refreshingCredential: fields["grant_type"] == "refresh_token")
        } else {
            data = try await SubscriptionHTTP.shared.request(config.tokenURL, body: JSONSerialization.data(withJSONObject: fields),
                refreshingCredential: fields["grant_type"] == "refresh_token")
        }
        return try ProviderTokens.decode(data, provider: provider)
    }

    public static func renew(_ old: SubscriptionCredential, provider: Provider) async throws -> SubscriptionCredential {
        guard let refresh = old.refreshToken, !refresh.isEmpty else { throw SubscriptionError.authentication }
        var fields = ["client_id": SubscriptionOAuthConfiguration(provider: provider).clientID,
                      "grant_type": "refresh_token", "refresh_token": refresh]
        if provider == .openai { fields["scope"] = "openid profile email" }
        var next = try await exchange(fields, provider: provider)
        next.refreshToken = next.refreshToken ?? old.refreshToken
        next.email = next.email ?? old.email; next.plan = next.plan ?? old.plan
        next.providerAccountID = next.providerAccountID ?? old.providerAccountID
        next.metadataCheckedAt = old.metadataCheckedAt
        return next
    }

    public static func usage(_ credential: SubscriptionCredential, provider: Provider) async throws -> (SubscriptionCredential, [UsageWindow]) {
        var credential = credential
        let windows: [UsageWindow]
        switch provider {
        case .openai:
            var headers = ["originator": "codex_cli_rs"]
            if let id = credential.providerAccountID, !id.isEmpty { headers["ChatGPT-Account-Id"] = id }
            let data = try await SubscriptionHTTP.shared.request(URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                bearer: credential.accessToken, headers: headers)
            let parsed = try OpenAIUsageSnapshot.parse(data)
            credential.plan = parsed.0 ?? credential.plan; windows = parsed.1
        case .claude:
            let data = try await SubscriptionHTTP.shared.request(URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                bearer: credential.accessToken, headers: ["anthropic-beta": "oauth-2025-04-20"])
            windows = try SubscriptionSnapshot.claude(data)
            if credential.metadataCheckedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true {
                if let profile = try? await SubscriptionHTTP.shared.request(URL(string: "https://api.anthropic.com/api/oauth/profile")!, bearer: credential.accessToken),
                   let json = try? JSONSerialization.jsonObject(with: profile) as? [String: Any] {
                    let identity = json["account"] as? [String: Any]; let org = json["organization"] as? [String: Any]
                    credential.email = identity?["email_address"] as? String ?? credential.email
                    let tier = org?["rate_limit_tier"] as? String ?? org?["subscription_type"] as? String ?? ""
                    credential.plan = tier.contains("max_20") ? "Max 20×" : tier.contains("max_5") ? "Max 5×" : tier.contains("max") ? "Max" : tier.contains("pro") ? "Pro" : credential.plan
                    credential.metadataCheckedAt = Date()
                }
            }
        case .grok:
            let headers = ["x-xai-token-auth": "xai-grok-cli"]
            let data = try await SubscriptionHTTP.shared.request(URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!, bearer: credential.accessToken, headers: headers)
            var parsed = try SubscriptionSnapshot.grok(data)
            if parsed.first?.usedPercent == nil,
               let wire = try? await SubscriptionHTTP.shared.request(URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!,
                    bearer: credential.accessToken, body: Data([0,0,0,0,0]), contentType: "application/grpc-web+proto", headers: ["x-grpc-web": "1"]),
               let fallback = try? GrokWireSnapshot.window(wire) {
                if parsed.isEmpty { parsed = [fallback] }
                else { parsed[0].usedPercent = fallback.usedPercent; parsed[0].resetsAt = parsed[0].resetsAt ?? fallback.resetsAt }
            }
            windows = parsed
            if credential.metadataCheckedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true,
               let data = try? await SubscriptionHTTP.shared.request(URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!, bearer: credential.accessToken, headers: headers),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                credential.plan = json["subscription_tier_display"] as? String ?? credential.plan; credential.metadataCheckedAt = Date()
            }
            credential.plan = credential.plan ?? "SuperGrok"
        case .grokBot:
            let data: Data
            do {
                data = try await SubscriptionHTTP.shared.request(URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!,
                    bearer: credential.accessToken, body: Data("{}".utf8), headers: ["Connect-Protocol-Version": "1"])
            } catch SubscriptionError.status(let code) where [403,404,415].contains(code) {
                guard let subject = ProviderTokens.claims(credential.accessToken)["sub"] as? String,
                      let user = subject.split(separator: "|").last, !user.isEmpty,
                      user.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0) }) else { throw SubscriptionError.authentication }
                data = try await SubscriptionHTTP.shared.request(URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!,
                    body: Data("{}".utf8), headers: ["Cookie": "WorkosCursorSessionToken=\(user)%3A%3A\(credential.accessToken)", "Origin": "https://cursor.com"])
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            credential.plan = json["grokPlanLabel"] as? String ?? credential.plan
            windows = try SubscriptionSnapshot.grokBot(data)
        }
        return (credential, windows)
    }
}
