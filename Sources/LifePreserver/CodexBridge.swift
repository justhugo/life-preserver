import AppKit
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

enum ConnectionError: LocalizedError {
    case missingHelper, unavailable, timeout, rejected, signedOut, invalidResponse
    var errorDescription: String? {
        switch self {
        case .missingHelper: return "Install Codex or the ChatGPT desktop app, then try again. Life Preserver uses the official Codex helper for secure sign-in."
        case .unavailable: return "The Codex helper stopped responding. Please try again."
        case .timeout: return "The provider took too long to respond. Check your connection and try again."
        case .rejected: return "The provider couldn’t complete this request. Try again, or reconnect your account."
        case .signedOut: return "Your session has ended. Reconnect this account in Settings."
        case .invalidResponse: return "The provider returned an unreadable response. Please try again later."
        }
    }
}

/// A dedicated, local, read-only client of OpenAI's documented app-server interface.
/// OAuth and token refresh stay inside the official helper; credentials use macOS Keychain.
@MainActor
final class CodexBridge {
    let accountID: UUID
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var sequence = 0
    private var ready = false
    private var startTask: Task<Void, Error>?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    var onLogin: ((Bool) -> Void)?

    init(accountID: UUID) { self.accountID = accountID }

    static var executable: URL? {
        // Resolve by bundle identity as well as name: desktop updates can rename the app.
        let installed = ["com.openai.codex", "com.openai.chat"].compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        let applications = installed + ["/Applications/Codex.app", "/Applications/ChatGPT.app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ChatGPT.app").path]
            .map { URL(fileURLWithPath: $0) }
        let paths = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codex").path]
            + applications.flatMap { application in
                ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                 "Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"]
                    .map { application.appendingPathComponent($0).path }
            } + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func start() async throws {
        if ready { return }
        if let startTask { return try await startTask.value }
        let task = Task { @MainActor in try await self.launch() }
        startTask = task
        defer { startTask = nil }
        try await task.value
    }

    private func launch() async throws {
        guard let executable = Self.executable else { throw ConnectionError.missingHelper }
        let directory = AppStore.supportDirectory.appendingPathComponent("Connections/\(accountID.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let child = Process()
        child.executableURL = executable
        child.arguments = ["app-server", "--stdio", "-c", "cli_auth_credentials_store=\"keyring\"",
            "-c", "analytics.enabled=false", "-c", "feedback.enabled=false"]
        // CODEX_HOME is the helper's documented configuration directory. It is isolated
        // per Life Preserver account; the user's own Codex environment is never changed.
        child.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin",
            "CODEX_HOME": directory.path, "LANG": "en_US.UTF-8"]
        child.currentDirectoryURL = directory
        let stdin = Pipe(), stdout = Pipe()
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        input = stdin; output = stdout; process = child
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.process === child else { return }
                if data.isEmpty { self.stop() } else { self.consume(data) }
            }
        }
        child.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                guard let self, self.process === terminated else { return }
                self.stop()
            }
        }
        do {
            try child.run()
            _ = try await request("initialize", params: ["clientInfo": [
                "name": "life_preserver", "title": "Life Preserver", "version": "1.0.0"]])
            try send(["method": "initialized", "params": [:]])
            ready = true
        } catch { stop(); throw error }
    }

    func request(_ method: String, params: [String: Any] = [:]) async throws -> Data {
        guard process?.isRunning == true else { throw ConnectionError.unavailable }
        sequence += 1
        let id = sequence
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                guard let self else { return }
                self.pending.removeValue(forKey: id)?.resume(throwing: ConnectionError.timeout)
                self.timeouts.removeValue(forKey: id)
            }
            do { try send(["method": method, "id": id, "params": params]) }
            catch {
                timeouts.removeValue(forKey: id)?.cancel()
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    func signIn() async throws -> String {
        try await start()
        let result = try await request("account/login/start", params: ["type": "chatgpt"])
        guard let json = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let loginID = json["loginId"] as? String,
              let address = json["authUrl"] as? String, let url = URL(string: address),
              url.scheme == "https", ["auth.openai.com", "chatgpt.com", "auth0.openai.com"].contains(url.host ?? "")
        else { throw ConnectionError.invalidResponse }
        guard NSWorkspace.shared.open(url) else { throw ConnectionError.unavailable }
        return loginID
    }

    func readAccount() async throws -> (String, String) {
        try await start()
        let data = try await request("account/read", params: ["refreshToken": true])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["account"] as? [String: Any], account["type"] as? String == "chatgpt"
        else { throw ConnectionError.signedOut }
        return (account["email"] as? String ?? "Personal", (account["planType"] as? String ?? "ChatGPT").capitalized)
    }

    func readUsage() async throws -> [UsageWindow] {
        try await start()
        return try CodexSnapshot.windows(from: await request("account/rateLimits/read"))
    }

    func stop() {
        ready = false
        output?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.fileHandleForWriting.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; buffer.removeAll()
        let callbacks = pending.values
        pending.removeAll()
        timeouts.values.forEach { $0.cancel() }; timeouts.removeAll()
        callbacks.forEach { $0.resume(throwing: ConnectionError.unavailable) }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input?.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 4_194_304 else { stop(); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if json["error"] != nil { continuation.resume(throwing: ConnectionError.rejected) }
                else if let result = json["result"], let encoded = try? JSONSerialization.data(withJSONObject: result) {
                    continuation.resume(returning: encoded)
                } else { continuation.resume(throwing: ConnectionError.invalidResponse) }
            } else if json["method"] as? String == "account/login/completed",
                      let params = json["params"] as? [String: Any] {
                onLogin?(params["success"] as? Bool == true)
            }
        }
    }
}
