import AppKit
import CryptoKit
import Network
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

struct SubscriptionOAuthConfiguration {
    let provider: Provider
    var clientID: String {
        provider == .claude ? "9d1c250a-e61b-44d9-88ed-5944d1962f5e" : "b1a00492-073a-47ea-816f-4c329264a828"
    }
    var authorizeURL: URL {
        URL(string: provider == .claude ? "https://claude.ai/oauth/authorize" : "https://auth.x.ai/oauth2/authorize")!
    }
    var tokenURL: URL {
        URL(string: provider == .claude ? "https://platform.claude.com/v1/oauth/token" : "https://auth.x.ai/oauth2/token")!
    }
    var scope: String {
        provider == .claude ? "user:profile" : "openid profile email offline_access grok-cli:access api:access"
    }
}

enum SubscriptionError: LocalizedError {
    case authentication, renewalRejected, response, denied, busyPort, timeout, rateLimited(Date), status(Int)
    var errorDescription: String? {
        switch self {
        case .authentication: "Your provider session has expired. Reconnect this account."
        case .renewalRejected: "Your saved provider sign-in has expired or been revoked. Reconnect this account in Settings → Accounts."
        case .response: "The provider didn’t return a readable subscription usage value. Try refreshing shortly."
        case .denied: "Sign-in was not approved. You can reconnect when you’re ready."
        case .busyPort: "The sign-in callback port is busy. Finish any other provider sign-in and try again."
        case .timeout: "Sign-in timed out. Please try again."
        case .rateLimited: "The provider has paused usage checks. Life Preserver will retry after the cooldown."
        case let .status(code): "The provider couldn’t complete the request (HTTP \(code)). Try again shortly."
        }
    }
}

/// Isolated, cache-free transport. Never forward credentials through redirects.
@MainActor
final class SubscriptionHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = SubscriptionHTTP()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func request(_ url: URL, bearer: String? = nil, body: Data? = nil,
                 contentType: String = "application/json", headers: [String: String] = [:],
                 refreshingCredential: Bool = false) async throws -> Data {
        precondition(url.scheme == "https")
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("LifePreserver/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse, data.count <= 4_194_304 else { throw SubscriptionError.response }
        if refreshingCredential, OAuthTokenFailure.requiresReconnect(status: response.statusCode, data: data) {
            throw SubscriptionError.renewalRejected
        }
        if response.statusCode == 401 { throw SubscriptionError.authentication }
        if response.statusCode == 429 {
            let delay = TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300
            throw SubscriptionError.rateLimited(Date().addingTimeInterval(max(60, min(3600, delay))))
        }
        guard (200..<300).contains(response.statusCode) else { throw SubscriptionError.status(response.statusCode) }
        if let status = response.value(forHTTPHeaderField: "grpc-status"), status != "0" { throw SubscriptionError.authentication }
        return data
    }

    func token(_ fields: [String: String], configuration: SubscriptionOAuthConfiguration) async throws -> SubscriptionCredential {
        let data: Data
        let refreshing = fields["grant_type"] == "refresh_token"
        if configuration.provider == .claude {
            data = try await request(configuration.tokenURL, body: JSONSerialization.data(withJSONObject: fields), refreshingCredential: refreshing)
        } else {
            var form = URLComponents(); form.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            data = try await request(configuration.tokenURL, body: Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8), contentType: "application/x-www-form-urlencoded", refreshingCredential: refreshing)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let token = json["access_token"] as? String, !token.isEmpty else { throw SubscriptionError.authentication }
        let identity = json["account"] as? [String: Any]
        return SubscriptionCredential(accessToken: token, refreshToken: json["refresh_token"] as? String,
            expiresAt: (json["expires_in"] as? Double).map { Date().addingTimeInterval($0) },
            email: identity?["email_address"] as? String, plan: nil)
    }
}

/// Native public-client Authorization Code + PKCE, with a loopback-only callback.
/// The browser owns password/MFA entry. Only tokens enter Life Preserver's Keychain.
@MainActor
final class SubscriptionSignIn {
    private var listener: NWListener?
    private var callback: CheckedContinuation<String, Error>?
    private var readiness: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var state = ""
    private var callbackHost = ""
    private var received = false

    func signIn(provider: Provider) async throws -> SubscriptionCredential {
        if provider == .grokBot { return try await GrokBotConnection.signIn() }
        let configuration = SubscriptionOAuthConfiguration(provider: provider)
        let verifier = try randomString()
        state = try randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let parameters = NWParameters.tcp
        let port: NWEndpoint.Port = provider == .claude ? NWEndpoint.Port(rawValue: 53692)! : .any
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let server = try NWListener(using: parameters)
        listener = server
        defer { cleanup() }
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection, data: Data()) }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            self?.fail(SubscriptionError.timeout)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readiness = continuation
            server.stateUpdateHandler = { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    switch status {
                    case .ready: self.readiness?.resume(); self.readiness = nil
                    case .failed: self.fail(SubscriptionError.busyPort)
                    default: break
                    }
                }
            }
            server.start(queue: .main)
        }
        guard let boundPort = server.port?.rawValue else { throw SubscriptionError.busyPort }
        callbackHost = "\(provider == .claude ? "localhost" : "127.0.0.1"):\(boundPort)"
        let redirect = "http://\(callbackHost)/callback"
        var components = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = ["client_id": configuration.clientID, "response_type": "code", "redirect_uri": redirect,
                     "scope": configuration.scope, "code_challenge": challenge, "code_challenge_method": "S256", "state": state]
        if provider == .claude { items["code"] = "true" }
        else { items["nonce"] = try randomString(); items["referrer"] = "grok-build" }
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let code = try await withCheckedThrowingContinuation { continuation in
            callback = continuation
            guard let url = components.url, NSWorkspace.shared.open(url) else { fail(SubscriptionError.denied); return }
        }
        try Task.checkCancellation()
        var fields = ["grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
                      "client_id": configuration.clientID, "code_verifier": verifier]
        if provider == .claude { fields["state"] = state }
        return try await SubscriptionHTTP.shared.token(fields, configuration: configuration)
    }

    func cancel() { fail(CancellationError()); cleanup() }
    private func cleanup() { timeout?.cancel(); listener?.cancel(); listener = nil }
    private func fail(_ error: Error) {
        readiness?.resume(throwing: error); readiness = nil
        callback?.resume(throwing: error); callback = nil
    }
    private func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SubscriptionError.response }
        return Data(bytes).base64URLEncoded()
    }
    private func receive(_ connection: NWConnection, data: Data) {
        if data.isEmpty { connection.start(queue: .main) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var all = data; if let chunk { all.append(chunk) }
                guard error == nil, all.count <= 16_384 else { connection.cancel(); return }
                guard let raw = String(data: all, encoding: .utf8), raw.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.receive(connection, data: all) }
                    return
                }
                let first = raw.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard first.count == 3, first[0] == "GET",
                      let url = URLComponents(string: "http://\(self.callbackHost)\(first[1])"), url.path == "/callback",
                      url.queryItems?.filter({ $0.name == "state" }).count == 1,
                      url.queryItems?.first(where: { $0.name == "state" })?.value == self.state,
                      !self.received else { self.respond(connection, status: "400 Bad Request", body: "Invalid sign-in callback."); return }
                if let code = url.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                    self.received = true
                    self.respond(connection, status: "200 OK", body: "Sign-in received. You can return to Life Preserver.")
                    self.callback?.resume(returning: code); self.callback = nil
                } else {
                    self.respond(connection, status: "400 Bad Request", body: "Sign-in was not completed. Return to Life Preserver to try again.")
                    self.fail(SubscriptionError.denied)
                }
            }
        }
    }
    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

private extension Data {
    func base64URLEncoded() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

@MainActor
final class SubscriptionUsageClient {
    private var cooldown: [UUID: Date] = [:]
    private var jobs: [UUID: (generation: UUID, task: Task<(SubscriptionCredential, [UsageWindow]), Error>)] = [:]

    func read(_ account: ProviderAccount) async throws -> (SubscriptionCredential, [UsageWindow]) {
        if let date = cooldown[account.id], date > Date() { throw SubscriptionError.rateLimited(date) }
        if let job = jobs[account.id] { return try await job.task.value }
        let generation = UUID()
        let job = Task { @MainActor in
            do { return try await self.fetch(account) }
            catch SubscriptionError.authentication {
                try Task.checkCancellation()
                // A revoked/early-expiring access token gets exactly one refresh attempt.
                let credential = try CredentialVault.read(account: account.id)
                try await self.renew(credential, for: account)
                return try await self.fetch(account)
            }
        }
        jobs[account.id] = (generation, job)
        defer { if jobs[account.id]?.generation == generation { jobs[account.id] = nil } }
        do { return try await job.value }
        catch { if case SubscriptionError.rateLimited(let until) = error { cooldown[account.id] = until }; throw error }
    }
    func invalidate(_ id: UUID) {
        jobs.removeValue(forKey: id)?.task.cancel()
        cooldown.removeValue(forKey: id)
    }
    func cancelAll() {
        for job in jobs.values { job.task.cancel() }
        jobs.removeAll()
    }
    func disconnect(_ id: UUID) throws {
        invalidate(id)
        try CredentialVault.remove(account: id)
    }
    private func renew(_ credential: SubscriptionCredential, for account: ProviderAccount) async throws {
        if account.provider == .grokBot {
            let renewed = try await GrokBotConnection.refresh(credential)
            try Task.checkCancellation()
            try CredentialVault.save(renewed, account: account.id)
            return
        }
        guard let refresh = credential.refreshToken else { throw SubscriptionError.authentication }
        let config = SubscriptionOAuthConfiguration(provider: account.provider)
        var renewed = try await SubscriptionHTTP.shared.token(["grant_type": "refresh_token", "refresh_token": refresh,
            "client_id": config.clientID], configuration: config)
        renewed.refreshToken = renewed.refreshToken ?? credential.refreshToken
        renewed.email = renewed.email ?? credential.email; renewed.plan = credential.plan
        renewed.metadataCheckedAt = credential.metadataCheckedAt
        try Task.checkCancellation()
        try CredentialVault.save(renewed, account: account.id)
    }
    private func fetch(_ account: ProviderAccount) async throws -> (SubscriptionCredential, [UsageWindow]) {
        var credential = try CredentialVault.read(account: account.id)
        if credential.expiresAt.map({ $0 < Date().addingTimeInterval(120) }) == true {
            try await renew(credential, for: account)
            credential = try CredentialVault.read(account: account.id)
        }
        let windows: [UsageWindow]
        if account.provider == .grokBot {
            let (plan, reading) = try await GrokBotConnection.usage(credential.accessToken)
            credential.plan = plan ?? credential.plan
            windows = reading
        } else if account.provider == .claude {
            let data = try await SubscriptionHTTP.shared.request(URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                bearer: credential.accessToken, headers: ["anthropic-beta": "oauth-2025-04-20"])
            windows = try SubscriptionSnapshot.claude(data)
            if credential.metadataCheckedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true {
                credential.metadataCheckedAt = Date()
                if let profile = try? await SubscriptionHTTP.shared.request(URL(string: "https://api.anthropic.com/api/oauth/profile")!, bearer: credential.accessToken),
                   let json = try? JSONSerialization.jsonObject(with: profile) as? [String: Any] {
                    let identity = json["account"] as? [String: Any]
                    let org = json["organization"] as? [String: Any]
                    credential.email = identity?["email_address"] as? String ?? identity?["email"] as? String ?? credential.email
                    let tier = org?["rate_limit_tier"] as? String ?? org?["subscription_type"] as? String ?? ""
                    credential.plan = tier.contains("max_20") ? "Max 20×" : tier.contains("max_5") ? "Max 5×" : tier.contains("max") ? "Max" : tier.contains("pro") ? "Pro" : nil
                }
            }
        } else {
            let headers = ["x-xai-token-auth": "xai-grok-cli"]
            let data = try await SubscriptionHTTP.shared.request(URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!,
                bearer: credential.accessToken, headers: headers)
            var parsed = try SubscriptionSnapshot.grok(data)
            if parsed.first?.usedPercent == nil {
                if let wire = try? await SubscriptionHTTP.shared.request(URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!,
                    bearer: credential.accessToken, body: Data([0,0,0,0,0]), contentType: "application/grpc-web+proto", headers: ["x-grpc-web": "1"]),
                   let fallback = try? GrokWireSnapshot.window(wire) {
                    if parsed.isEmpty { parsed = [fallback] }
                    else { parsed[0].usedPercent = fallback.usedPercent; parsed[0].resetsAt = parsed[0].resetsAt ?? fallback.resetsAt }
                }
            }
            windows = parsed
            if credential.metadataCheckedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true {
                credential.metadataCheckedAt = Date()
                if let settings = try? await SubscriptionHTTP.shared.request(URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!, bearer: credential.accessToken, headers: headers),
               let json = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] {
                credential.plan = json["subscription_tier_display"] as? String ?? credential.plan
                }
            }
            credential.plan = credential.plan ?? "SuperGrok"
        }
        try Task.checkCancellation()
        try CredentialVault.save(credential, account: account.id)
        return (credential, windows)
    }
}
