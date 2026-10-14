import Combine
import CloudKit
import Foundation
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverSync
#endif

@MainActor
final class MobileSharing: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "Direct mobile checks are off."
    @Published private(set) var busy = false
    @Published private(set) var lastPublished: Date?
    let configured = Bundle.main.object(forInfoDictionaryKey: "LifePreserverCloudSyncConfigured") as? String == "YES"
    private var worker: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var lastAccounts: [ProviderAccount] = []
    private var pending = false

    init() {
        enabled = UserDefaults.standard.bool(forKey: "mobileSharingEnabled")
        if enabled { status = "Preparing secure sign-ins for direct mobile checks…" }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do { try await Self.validateOwner() }
                catch SessionSharingError.changed {
                    self.worker?.cancel(); self.pending = false; self.enabled = false; self.lastPublished = nil
                    self.status = "Your iCloud account changed. Turn on direct mobile checks again to connect this account."
                } catch { /* A transient account notification must not turn sharing off. */ }
            }
        }
    }
    @discardableResult static func validateOwner() async throws -> String {
        let owner = try await SharedProviderSessions.shared.ownerID()
        if let previous = UserDefaults.standard.string(forKey: "directSharingOwner"), previous != owner {
            UserDefaults.standard.set(false, forKey: "mobileSharingEnabled")
            throw SessionSharingError.changed
        }
        UserDefaults.standard.set(owner, forKey: "directSharingOwner")
        return owner
    }
    func setEnabled(_ value: Bool, accounts: [ProviderAccount]) {
        guard configured, !busy else { return }
        if value {
            // Explicit opt-in authorizes the currently signed-in iCloud account.
            UserDefaults.standard.removeObject(forKey: "directSharingOwner")
            enabled = true; UserDefaults.standard.set(true, forKey: "mobileSharingEnabled"); update(accounts)
        }
        else {
            worker = Task {
                busy = true
                defer { busy = false; worker = nil }
                do {
                    try await Self.validateOwner()
                    let shared = SharedProviderSessions.shared
                    // Copy canonical sessions back locally before removing the shared copies.
                    for account in accounts where account.kind != .manual && account.kind != .demo {
                        if try await shared.contains(account.id) {
                            let credential = try await shared.currentCredential(for: SharedProviderAccount(id: account.id, provider: account.provider, plan: account.plan))
                            try CredentialVault.save(credential, account: account.id)
                        }
                    }
                    try await shared.setAccounts([])
                    for account in accounts where account.kind != .manual && account.kind != .demo { try await shared.remove(account.id) }
                    enabled = false; lastPublished = nil
                    UserDefaults.standard.set(false, forKey: "mobileSharingEnabled")
                    status = "Direct mobile checks are off. Shared sign-ins have been removed."
                } catch { status = Self.message(error) }
            }
        }
    }
    func update(_ accounts: [ProviderAccount]) {
        lastAccounts = accounts
        guard enabled, configured else { return }
        pending = true
        guard worker == nil else { return }
        worker = Task {
            busy = true
            defer { busy = false; worker = nil }
            while pending && enabled && !Task.isCancelled {
                pending = false
                do {
                    let owner = try await Self.validateOwner()
                    let accounts = lastAccounts.filter { $0.kind != .manual && $0.kind != .demo }
                    var directory: [SharedProviderAccount] = []
                    for account in accounts {
                        let shared = SharedProviderAccount(id: account.id, provider: account.provider, plan: account.plan)
                        if !(try await SharedProviderSessions.shared.contains(account.id)) {
                            try await SharedProviderSessions.shared.share(SubscriptionUsageClient.localCredential(account), account: shared, expectedOwner: owner)
                        }
                        directory.append(shared)
                    }
                    try Task.checkCancellation()
                    try await SharedProviderSessions.shared.setAccounts(directory)
                    lastPublished = Date()
                    status = "Secure sign-ins are ready. Your iPhone and iPad check providers directly, even while this Mac is asleep."
                } catch { if !Task.isCancelled { status = Self.message(error) } }
            }
        }
    }
    static func message(_ error: Error) -> String {
        if error is CKError || error is PrivateUsageCloud.SyncError { return PrivateUsageCloud.message(for: error) }
        return error.localizedDescription
    }
    func retry() { update(lastAccounts) }
    func shutdown() { worker?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}
