import Foundation
import Testing
@testable import LifePreserverCore

@Test func mobileExportExcludesLabelsErrorsAndNonLiveConnections() throws {
    var account = ProviderAccount(provider: .claude, kind: .claudeOAuth,
        label: "PRIVATE-EMAIL", plan: "Max", windows: [UsageWindow(id: "session", title: "5-hour session", usedPercent: 0)], updatedAt: Date())
    account.error = "PRIVATE-ERROR-TOKEN"
    let snapshot = MobileSnapshot(accounts: [account] + SampleData.accounts() + [ProviderAccount(provider: .grok, kind: .manual)], sharingEnabled: true)
    let data = try JSONEncoder().encode(snapshot)
    let text = String(decoding: data, as: UTF8.self)
    #expect(snapshot.accounts.count == 1)
    #expect(!text.contains("PRIVATE"))
    #expect(!text.contains("label"))
    #expect(!text.contains("access_token"))
    #expect(!text.contains("refresh_token"))
    #expect(snapshot.accounts[0].displayAccount.error == "Check this connection on your Mac.")
    #expect(snapshot.accounts[0].displayAccount.windows[0].remainingPercent == 100)
    #expect(try MobileSnapshot.decode(data) == snapshot)
}

@Test func stoppingSharingClearsAllRemoteAccounts() throws {
    let snapshot = MobileSnapshot(accounts: [ProviderAccount(provider: .openai, kind: .codex)], sharingEnabled: false)
    #expect(snapshot.accounts.isEmpty)
    #expect(!snapshot.sharingEnabled)
    #expect(try MobileSnapshot.decode(JSONEncoder().encode(snapshot)) == snapshot)
}

@Test func syncedReadingsRetainProviderTimestampAndResetFreshness() {
    let now = Date()
    let original = ProviderAccount(provider: .claude, kind: .claudeOAuth,
        windows: [UsageWindow(id: "session", title: "5-hour session", usedPercent: 83, resetsAt: now.addingTimeInterval(120))], updatedAt: now.addingTimeInterval(-800))
    let synced = MobileSnapshot(accounts: [original], sharingEnabled: true, at: now).accounts[0].displayAccount
    #expect(!synced.isStale(at: now))
    #expect(synced.isStale(at: now.addingTimeInterval(121)))
    #expect(synced.windows[0].remainingPercent == 17)
    #expect(synced.updatedAt == original.updatedAt)
}

@Test func unsupportedMobileSchemaIsRejected() throws {
    let data = try JSONEncoder().encode(MobileSnapshot(accounts: [], sharingEnabled: true))
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json["version"] = 2
    let unsupported = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: MobileSnapshot.SnapshotError.self) { try MobileSnapshot.decode(unsupported) }
}
