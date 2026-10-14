import AppKit
import CryptoKit
import Network
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverProviders
import LifePreserverSync
#endif

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
    private var callbackPath = "/callback"
    private var received = false

    func signIn(provider: Provider) async throws -> SubscriptionCredential {
        if provider == .grokBot { return try await GrokBotConnection.signIn() }
        let configuration = SubscriptionOAuthConfiguration(provider: provider)
        let verifier = try randomString()
        state = try randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let parameters = NWParameters.tcp
        let port: NWEndpoint.Port = provider == .openai ? NWEndpoint.Port(rawValue: 1455)! : provider == .claude ? NWEndpoint.Port(rawValue: 53692)! : .any
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
        callbackHost = "\(provider == .grok ? "127.0.0.1" : "localhost"):\(boundPort)"
        callbackPath = provider == .openai ? "/auth/callback" : "/callback"
        let redirect = "http://\(callbackHost)\(callbackPath)"
        var components = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = ["client_id": configuration.clientID, "response_type": "code", "redirect_uri": redirect,
                     "scope": configuration.scope, "code_challenge": challenge, "code_challenge_method": "S256", "state": state]
        if provider == .openai {
            items["codex_cli_simplified_flow"] = "true"; items["originator"] = "codex_cli_rs"
            items["id_token_add_organizations"] = "true"
        }
        else if provider == .claude { items["code"] = "true" }
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
        return try await DirectProviderClient.exchange(fields, provider: provider)
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
                      let url = URLComponents(string: "http://\(self.callbackHost)\(first[1])"), url.path == self.callbackPath,
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
