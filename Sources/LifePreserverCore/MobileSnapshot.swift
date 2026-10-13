import Foundation

/// The complete allowlist of data permitted to leave the Mac. Account labels,
/// transport errors, connection directories and credentials are never exported.
public struct MobileSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let publishedAt: Date
    public let sharingEnabled: Bool
    public let accounts: [MobileAccount]

    public init(accounts: [ProviderAccount], sharingEnabled: Bool, at date: Date = Date()) {
        version = 1
        publishedAt = date
        self.sharingEnabled = sharingEnabled
        self.accounts = sharingEnabled ? accounts.filter { $0.kind != .demo && $0.kind != .manual }.map(MobileAccount.init) : []
    }

    public static func decode(_ data: Data) throws -> MobileSnapshot {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1, result.sharingEnabled || result.accounts.isEmpty else {
            throw SnapshotError.unsupported
        }
        return result
    }

    public enum SnapshotError: Error { case unsupported }
}

public struct MobileAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let provider: Provider
    public let plan: String
    public let windows: [UsageWindow]
    public let updatedAt: Date?
    public let needsAttention: Bool

    fileprivate init(_ account: ProviderAccount) {
        id = account.id
        provider = account.provider
        plan = account.plan
        windows = account.windows
        updatedAt = account.updatedAt
        needsAttention = account.error != nil
    }

    public var displayAccount: ProviderAccount {
        ProviderAccount(id: id, provider: provider, kind: .codex, plan: plan,
                        windows: windows, updatedAt: updatedAt,
                        error: needsAttention ? "Check this connection on your Mac." : nil)
    }
}

/// A successful iCloud read alone does not prove that the Mac is still updating.
/// Use the original publication time, not the time cached data was loaded.
public enum MobileLinkState: Sendable {
    case unchecked, waiting, sharingOff, healthy, stale, failed

    public static func evaluate(snapshot: MobileSnapshot?, lastChecked: Date?, checkFailed: Bool, at now: Date = Date()) -> Self {
        if checkFailed { return .failed }
        guard lastChecked != nil else { return .unchecked }
        guard let snapshot else { return .waiting }
        guard snapshot.sharingEnabled else { return .sharingOff }
        return now.timeIntervalSince(snapshot.publishedAt) > 900 ? .stale : .healthy
    }

    public var title: String {
        switch self {
        case .unchecked: "Not checked yet"
        case .waiting: "Waiting for your Mac"
        case .sharingOff: "Sharing is off"
        case .healthy: "Mac sync is healthy"
        case .stale: "No recent Mac update"
        case .failed: "Connection check failed"
        }
    }
}
