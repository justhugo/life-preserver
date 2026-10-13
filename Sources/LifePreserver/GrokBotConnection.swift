import AppKit
import CryptoKit
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

/// The browser challenge/poll flow used by the provider's native client.
/// A new, isolated session; never reads Grok Bot's own credential storage.
@MainActor
enum GrokBotConnection {
    static func signIn() async throws -> SubscriptionCredential {
        var bytes = [UInt8](repeating:0, count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw SubscriptionError.response }
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data:Data(verifier.utf8))))
        let id = UUID().uuidString
        var login = URLComponents(string:"https://cursor.com/loginDeepControl")!
        login.queryItems = [URLQueryItem(name:"challenge",value:challenge), URLQueryItem(name:"uuid",value:id),
            URLQueryItem(name:"mode",value:"login"), URLQueryItem(name:"redirectTarget",value:"cli")]
        guard let url = login.url, NSWorkspace.shared.open(url) else { throw SubscriptionError.denied }
        var poll = URLComponents(string:"https://api2.cursor.sh/auth/poll")!
        poll.queryItems = [URLQueryItem(name:"uuid",value:id),URLQueryItem(name:"verifier",value:verifier)]
        let deadline = Date().addingTimeInterval(300)
        var attempts = 0
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                let data = try await SubscriptionHTTP.shared.request(poll.url!)
                return try credential(data, camelCase:true)
            } catch SubscriptionError.status(404) {
                attempts += 1
                try await Task.sleep(for:.seconds(min(5,1+Double(attempts)/4)))
            }
        }
        throw SubscriptionError.timeout
    }

    static func refresh(_ old: SubscriptionCredential) async throws -> SubscriptionCredential {
        guard let refresh = old.refreshToken else { throw SubscriptionError.authentication }
        let body = try JSONSerialization.data(withJSONObject:["client_id":"KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
            "grant_type":"refresh_token","refresh_token":refresh])
        let data = try await SubscriptionHTTP.shared.request(URL(string:"https://api2.cursor.sh/oauth/token")!,body:body)
        var renewed = try credential(data,camelCase:false)
        renewed.refreshToken = renewed.refreshToken ?? old.refreshToken
        renewed.email = renewed.email ?? old.email; renewed.plan = old.plan
        renewed.metadataCheckedAt = old.metadataCheckedAt
        return renewed
    }

    static func usage(_ token: String) async throws -> (String?, [UsageWindow]) {
        let data: Data
        do {
            data = try await SubscriptionHTTP.shared.request(URL(string:"https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!,
                bearer:token,body:Data("{}".utf8),headers:["Connect-Protocol-Version":"1"])
        } catch SubscriptionError.status(let status) where [403,404,415].contains(status) {
            // Dashboard compatibility path, scoped to the same Cursor session and host.
            guard let subject = payload(token)["sub"] as? String,
                  let user = subject.split(separator:"|").last, !user.isEmpty,
                  user.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"._-")).contains($0) })
            else { throw SubscriptionError.authentication }
            let cookie = "WorkosCursorSessionToken=\(user)%3A%3A\(token)"
            data = try await SubscriptionHTTP.shared.request(URL(string:"https://cursor.com/api/dashboard/get-sand-usage-status")!,
                body:Data("{}".utf8),headers:["Cookie":cookie,"Origin":"https://cursor.com"])
        }
        let json = try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
        return (json["grokPlanLabel"] as? String, try SubscriptionSnapshot.grokBot(data))
    }

    private static func credential(_ data: Data, camelCase: Bool) throws -> SubscriptionCredential {
        let json = try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
        guard let access = json[camelCase ? "accessToken" : "access_token"] as? String, !access.isEmpty else { throw SubscriptionError.authentication }
        let claims = payload(access)
        return SubscriptionCredential(accessToken:access,refreshToken:json[camelCase ? "refreshToken" : "refresh_token"] as? String,
            expiresAt:(claims["exp"] as? Double).map { Date(timeIntervalSince1970:$0) },email:claims["email"] as? String,plan:nil)
    }
    // JWT claims are display/expiry hints only; the provider validates authorization.
    private static func payload(_ token:String) -> [String:Any] {
        let parts = token.split(separator:".")
        guard parts.count == 3 else { return [:] }
        var text = String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        text += String(repeating:"=",count:(4-text.count%4)%4)
        guard let data = Data(base64Encoded:text),data.count < 32_768,
              let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return object
    }
    private static func base64URL(_ data:Data) -> String {
        data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
}
