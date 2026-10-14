import Foundation
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverProviders
import LifePreserverSync
#endif

@MainActor
final class SubscriptionUsageClient {
    static var sharingEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LifePreserverCloudSyncConfigured") as? String == "YES"
            && UserDefaults.standard.bool(forKey: "mobileSharingEnabled")
    }
    private var cooldown: [UUID: Date] = [:]
    private var jobs: [UUID: (generation: UUID, task: Task<(SubscriptionCredential, [UsageWindow]), Error>)] = [:]

    static func localCredential(_ account: ProviderAccount) throws -> SubscriptionCredential {
        do { return try CredentialVault.read(account: account.id) }
        catch CredentialVault.VaultError.status(let status) where status == -25300 && account.provider == .openai {
            return try LegacyOpenAISession.importOwned(account: account.id)
        }
    }
    func read(_ account: ProviderAccount) async throws -> (SubscriptionCredential, [UsageWindow]) {
        if let until = cooldown[account.id], until > Date() { throw SubscriptionError.rateLimited(until) }
        if let job = jobs[account.id] { return try await job.task.value }
        let generation = UUID()
        let task = Task { @MainActor in try await self.fetch(account) }
        jobs[account.id] = (generation, task)
        defer { if jobs[account.id]?.generation == generation { jobs[account.id] = nil } }
        do { return try await task.value }
        catch { if case SubscriptionError.rateLimited(let until) = error { cooldown[account.id] = until }; throw error }
    }
    private func fetch(_ account: ProviderAccount) async throws -> (SubscriptionCredential, [UsageWindow]) {
        var credential: SubscriptionCredential
        let sharing = Self.sharingEnabled
        let shared = SharedProviderAccount(id: account.id, provider: account.provider, plan: account.plan)
        if sharing {
            let owner = try await MobileSharing.validateOwner()
            if !(try await SharedProviderSessions.shared.contains(account.id)) {
                try await SharedProviderSessions.shared.share(Self.localCredential(account), account: shared, expectedOwner: owner)
            }
            credential = try await SharedProviderSessions.shared.credential(for: shared) {
                try await DirectProviderClient.renew($0, provider: account.provider)
            }
        } else {
            credential = try Self.localCredential(account)
            if credential.expiresAt.map({ $0 <= Date().addingTimeInterval(120) }) == true {
                credential = try await DirectProviderClient.renew(credential, provider: account.provider)
                try CredentialVault.save(credential, account: account.id)
            }
        }
        let result: (SubscriptionCredential, [UsageWindow])
        do { result = try await DirectProviderClient.usage(credential, provider: account.provider) }
        catch SubscriptionError.authentication {
            if sharing {
                credential = try await SharedProviderSessions.shared.credential(for: shared, rejectedToken: credential.accessToken) {
                    try await DirectProviderClient.renew($0, provider: account.provider)
                }
            } else {
                credential = try await DirectProviderClient.renew(credential, provider: account.provider)
                try CredentialVault.save(credential, account: account.id)
            }
            result = try await DirectProviderClient.usage(credential, provider: account.provider)
        }
        // Never write display metadata back over a shared token renewed by another device.
        try CredentialVault.save(result.0, account: account.id)
        try Task.checkCancellation()
        return result
    }
    func invalidate(_ id: UUID) { jobs.removeValue(forKey: id)?.task.cancel(); cooldown[id] = nil }
    func cancelAll() { jobs.values.forEach { $0.task.cancel() }; jobs.removeAll() }
    func disconnect(_ id: UUID) throws { invalidate(id); try CredentialVault.remove(account: id) }
}
