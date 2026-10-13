import CloudKit
import Combine
import Foundation

@MainActor
final class MobileStore: ObservableObject {
    @Published private(set) var snapshot: MobileSnapshot?
    @Published private(set) var refreshing = false
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checkFailed = false
    @Published private(set) var diagnostic: String?
    let preview: Bool
    private let cloud = PrivateUsageCloud()
    private var owner: String?
    private var epoch = UUID()
    private var observer: NSObjectProtocol?
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mobile-readings.json")
    }
    private struct Cache: Codable { let owner: String; let snapshot: MobileSnapshot }

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            // Preview is an explicit mode. Export excludes demo connections.
            let accounts = SampleData.accounts().map { item -> ProviderAccount in
                var item = item; item.kind = .codex; return item
            }
            snapshot = MobileSnapshot(accounts: accounts, sharingEnabled: true)
            return
        }
        // Do not expose a persisted snapshot before checking the iCloud identity.
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clearCache(); self?.message = "Your iCloud account changed. Pull to refresh to connect again." }
        }
    }

    func refresh() async {
        guard !preview, !refreshing else { return }
        refreshing = true
        let currentEpoch = epoch
        var stage = "iCloud account"
        defer { refreshing = false }
        do {
            let currentOwner = try await cloud.ownerID()
            guard currentEpoch == epoch else { return }
            if owner != currentOwner {
                snapshot = nil
                owner = currentOwner
                if let data = try? Data(contentsOf: Self.cacheURL),
                   let cache = try? JSONDecoder().decode(Cache.self, from: data),
                   cache.owner == currentOwner, cache.snapshot.version == 1 {
                    snapshot = cache.snapshot
                }
            }
            stage = "shared reading"
            let reading = try await cloud.fetch()
            guard currentEpoch == epoch else { return }
            snapshot = reading
            lastChecked = Date()
            message = nil
            checkFailed = false
            diagnostic = nil
            #if DEBUG
            print("Life Preserver sync: checked; snapshot=\(reading == nil ? "none" : reading!.sharingEnabled ? "enabled" : "disabled")")
            #endif
            if let reading {
                do {
                    try FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(Cache(owner: currentOwner, snapshot: reading)).write(to: Self.cacheURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                } catch { message = "Readings are up to date, but couldn’t be saved for offline viewing." }
            } else { try? FileManager.default.removeItem(at: Self.cacheURL) }
        } catch {
            guard currentEpoch == epoch else { return }
            if Task.isCancelled || PrivateUsageCloud.isCancellation(error) { return }
            if error as? PrivateUsageCloud.SyncError == .signIn || (error as? CKError)?.code == .notAuthenticated {
                clearCache()
            }
            message = PrivateUsageCloud.message(for: error)
            checkFailed = true
            diagnostic = "\(stage): \(PrivateUsageCloud.diagnosticCode(for: error))"
            #if DEBUG
            print("Life Preserver sync: \(diagnostic!)")
            #endif
        }
    }

    private func clearCache() {
        epoch = UUID()
        snapshot = nil
        owner = nil
        lastChecked = nil
        checkFailed = false
        diagnostic = nil
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }
}
