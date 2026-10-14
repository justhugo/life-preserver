import AppKit
import CryptoKit
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverProviders
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
                return try ProviderTokens.decode(data, provider: .grokBot, camelCase: true)
            } catch SubscriptionError.status(404) {
                attempts += 1
                try await Task.sleep(for:.seconds(min(5,1+Double(attempts)/4)))
            }
        }
        throw SubscriptionError.timeout
    }

    private static func base64URL(_ data:Data) -> String {
        data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
}
