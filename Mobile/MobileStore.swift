import CloudKit
import Combine
import Foundation

@MainActor
final class MobileStore: ObservableObject {
    @Published private(set) var accounts: [ProviderAccount] = []
    @Published private(set) var refreshing = false
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checkFailed = false
    let preview: Bool
    private let sessions = SharedProviderSessions.shared
    private var owner: String?
    private var epoch = UUID()
    private var observer: NSObjectProtocol?
    private var cooldown: [UUID: Date] = [:]
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("direct-readings-v2.json")
    }
    private struct Cache: Codable { let owner: String; let accounts: [ProviderAccount]; let checked: Date? }

    init(preview: Bool = false) {
        self.preview = preview
        if preview { accounts = SampleData.accounts(); return }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clearCache(); self?.message = "Your iCloud account changed. Refresh to load this account’s sign-ins." }
        }
    }
    func refresh() async {
        guard !preview, !refreshing else { return }
        refreshing = true
        let currentEpoch = epoch
        defer { refreshing = false }
        do {
            let currentOwner = try await sessions.ownerID()
            guard currentEpoch == epoch else { return }
            if owner != currentOwner {
                accounts = []; owner = currentOwner; lastChecked = nil
                if let bytes = try? Data(contentsOf: Self.cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: bytes), cache.owner == currentOwner {
                    accounts = cache.accounts; lastChecked = cache.checked
                }
            }
            let directory = try await sessions.accounts()
            guard currentEpoch == epoch else { return }
            accounts = directory.map { item in accounts.first(where: { $0.id == item.id }) ?? item.displayAccount }
            message = directory.isEmpty ? "Open the updated Mac app once and enable direct mobile checks in Settings → iPhone & iPad." : nil
            await withTaskGroup(of: Void.self) { group in
                for account in directory { group.addTask { await self.refreshAccount(account, epoch: currentEpoch) } }
            }
            guard currentEpoch == epoch, !Task.isCancelled else { return }
            checkFailed = accounts.contains { $0.error != nil }
            if accounts.contains(where: { $0.error == nil && $0.updatedAt != nil }) { lastChecked = Date() }
            try FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Only display readings enter the offline cache; no credential or encrypted session payload.
            try JSONEncoder().encode(Cache(owner: currentOwner, accounts: accounts, checked: lastChecked)).write(to: Self.cacheURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            guard currentEpoch == epoch, !Task.isCancelled, !PrivateUsageCloud.isCancellation(error) else { return }
            if error as? PrivateUsageCloud.SyncError == .signIn || (error as? CKError)?.code == .notAuthenticated { clearCache() }
            checkFailed = true
            message = error is CKError || error is PrivateUsageCloud.SyncError ? PrivateUsageCloud.message(for: error) : error.localizedDescription
        }
    }
    private func refreshAccount(_ account: SharedProviderAccount, epoch expected: UUID) async {
        do {
            if let until = cooldown[account.id], until > Date() { throw SubscriptionError.rateLimited(until) }
            var credential = try await sessions.credential(for: account) { try await DirectProviderClient.renew($0, provider: account.provider) }
            let result: (SubscriptionCredential, [UsageWindow])
            do { result = try await DirectProviderClient.usage(credential, provider: account.provider) }
            catch SubscriptionError.authentication {
                credential = try await sessions.credential(for: account, rejectedToken: credential.accessToken) { try await DirectProviderClient.renew($0, provider: account.provider) }
                result = try await DirectProviderClient.usage(credential, provider: account.provider)
            }
            guard expected == epoch, !Task.isCancelled, let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
            accounts[index].windows = result.1; accounts[index].plan = result.0.plan ?? account.plan
            accounts[index].updatedAt = Date()
            accounts[index].error = result.1.isEmpty || result.1.allSatisfy({ $0.usedPercent == nil }) ? "The provider hasn’t reported a usage reading yet." : nil
            #if DEBUG
            print("Life Preserver direct check: \(account.provider.rawValue) \(accounts[index].error == nil ? "success" : "no reading")")
            #endif
        } catch {
            guard expected == epoch, !Task.isCancelled, !PrivateUsageCloud.isCancellation(error), let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
            if case SubscriptionError.rateLimited(let until) = error { cooldown[account.id] = until }
            accounts[index].error = error is CKError ? PrivateUsageCloud.message(for: error) : error.localizedDescription
            #if DEBUG
            print("Life Preserver direct check: \(account.provider.rawValue) failed: \((error as NSError).domain)/\((error as NSError).code)")
            #endif
        }
    }
    private func clearCache() {
        epoch = UUID(); accounts = []; owner = nil; lastChecked = nil; cooldown.removeAll()
        checkFailed = false
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }
}
