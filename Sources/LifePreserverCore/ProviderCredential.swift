import Foundation

/// App-owned sign-in data. Persist only in Keychain or an authenticated encrypted envelope.
public struct SubscriptionCredential: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var email: String?
    public var plan: String?
    public var metadataCheckedAt: Date?
    public var providerAccountID: String?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil,
                email: String? = nil, plan: String? = nil, metadataCheckedAt: Date? = nil,
                providerAccountID: String? = nil) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
        self.email = email; self.plan = plan; self.metadataCheckedAt = metadataCheckedAt
        self.providerAccountID = providerAccountID
    }
}

public struct SharedProviderAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let provider: Provider
    public let plan: String
    public init(id: UUID, provider: Provider, plan: String) {
        self.id = id; self.provider = provider; self.plan = plan
    }
    public var displayAccount: ProviderAccount {
        ProviderAccount(id: id, provider: provider,
            kind: provider == .openai ? .codex : provider == .claude ? .claudeOAuth : provider == .grokBot ? .grokBotOAuth : .grokOAuth,
            plan: plan)
    }
}
