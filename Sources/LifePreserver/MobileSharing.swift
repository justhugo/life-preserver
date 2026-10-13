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
    @Published private(set) var status = "Sharing is off."
    @Published private(set) var busy = false
    @Published private(set) var lastPublished: Date?
    let configured = Bundle.main.object(forInfoDictionaryKey: "LifePreserverCloudSyncConfigured") as? String == "YES"
    private let cloud = PrivateUsageCloud()
    private var pending: MobileSnapshot?
    private var worker: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var lastAccounts: [ProviderAccount] = []

    init() {
        enabled = UserDefaults.standard.bool(forKey: "mobileSharingEnabled")
        if enabled { status = "Waiting to sync your readings…" }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // A new iCloud account must explicitly opt in again. Do not send a
                // clearing snapshot to a different account after a sign-out.
                self.pending = nil
                self.worker?.cancel()
                self.enabled = false
                self.lastPublished = nil
                UserDefaults.standard.set(false, forKey: "mobileSharingEnabled")
                UserDefaults.standard.set(false, forKey: "mobileClearPending")
                self.status = "Your iCloud account changed. Turn sharing on again to use this account."
            }
        }
    }

    func setEnabled(_ value: Bool, accounts: [ProviderAccount]) {
        guard configured else { status = "Install the iCloud-enabled Mac build to share readings."; return }
        enabled = value
        UserDefaults.standard.set(value, forKey: "mobileSharingEnabled")
        UserDefaults.standard.set(!value, forKey: "mobileClearPending")
        update(accounts)
    }

    func update(_ accounts: [ProviderAccount]) {
        lastAccounts = accounts
        guard configured else { return }
        guard enabled || UserDefaults.standard.bool(forKey: "mobileClearPending") else { return }
        pending = MobileSnapshot(accounts: accounts, sharingEnabled: enabled)
        startWorker()
    }

    func retry() { update(lastAccounts) }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task {
            busy = true
            defer { busy = false; worker = nil }
            while let snapshot = pending, !Task.isCancelled {
                pending = nil
                status = snapshot.sharingEnabled ? "Syncing readings…" : "Clearing shared readings…"
                do {
                    try await cloud.publish(snapshot)
                    guard !Task.isCancelled else { return }
                    lastPublished = snapshot.sharingEnabled ? snapshot.publishedAt : nil
                    if !snapshot.sharingEnabled { UserDefaults.standard.set(false, forKey: "mobileClearPending") }
                    status = snapshot.sharingEnabled ? "Your mobile readings are up to date." : "Sharing is off. The iCloud readings have been cleared."
                } catch {
                    guard !Task.isCancelled else { return }
                    status = PrivateUsageCloud.message(for: error)
                    if !enabled { status += " Shared readings haven’t been cleared yet. Keep the Mac online and retry." }
                    // A newer queued state (especially stopping sharing) still runs.
                    // Otherwise the next regular Mac refresh or Retry tries again.
                }
            }
        }
    }

    func shutdown() {
        worker?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
