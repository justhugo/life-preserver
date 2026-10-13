import Foundation

public enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openai, claude, grok, grokBot
    public var id: String { rawValue }
    public var name: String {
        switch self { case .claude: "Claude"; case .openai: "OpenAI"; case .grok: "Grok"; case .grokBot: "Grok Bot" }
    }
    public var company: String {
        switch self { case .claude: "Anthropic"; case .openai: "OpenAI · ChatGPT"; case .grok: "SpaceXAI"; case .grokBot: "Cursor · SpaceXAI" }
    }
    public var usageURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/settings/usage")!
        case .openai: URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .grok: URL(string: "https://grok.com")!
        case .grokBot: URL(string: "https://cursor.com/dashboard?tab=usage")!
        }
    }
}

public enum ConnectionKind: String, Codable, Sendable { case codex, claudeOAuth, grokOAuth, grokBotOAuth, manual, demo }
public enum Pressure: Int, Comparable, Sendable {
    case unknown = -1, comfortable = 0, watch = 1, critical = 2, exhausted = 3
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public init(usedPercent: Double?) {
        guard let value = usedPercent, value.isFinite else { self = .unknown; return }
        switch value {
        case 100...: self = .exhausted
        case 90..<100: self = .critical
        case 70..<90: self = .watch
        default: self = .comfortable
        }
    }
    public var label: String {
        switch self {
        case .unknown: "No reading"
        case .comfortable: "Looking good"
        case .watch: "Keep an eye on it"
        case .critical: "Running low"
        case .exhausted: "Limit reached"
        }
    }
}

public struct UsageWindow: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double?
    public var durationMinutes: Int?
    public var resetsAt: Date?
    public var overviewEligible: Bool?
    public init(id: String, title: String, usedPercent: Double?, durationMinutes: Int? = nil, resetsAt: Date? = nil, overviewEligible: Bool = true) {
        self.id = id; self.title = title
        self.usedPercent = usedPercent.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        self.durationMinutes = durationMinutes; self.resetsAt = resetsAt
        self.overviewEligible = overviewEligible
    }
    public var remainingPercent: Double? { usedPercent.map { 100 - $0 } }
    public var pressure: Pressure { Pressure(usedPercent: usedPercent) }
    public func resetIsPast(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
    public func resetText(at now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset not provided" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Awaiting new reading" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Resets in \(hours)h \(minutes % 60)m" }
        return "Resets in \(hours / 24)d \(hours % 24)h"
    }
}

public struct ProviderAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var provider: Provider
    public var kind: ConnectionKind
    public var label: String
    public var plan: String
    public var windows: [UsageWindow]
    public var updatedAt: Date?
    public var error: String?
    public init(id: UUID = UUID(), provider: Provider, kind: ConnectionKind, label: String = "Personal", plan: String = "", windows: [UsageWindow] = [], updatedAt: Date? = nil, error: String? = nil) {
        self.id = id; self.provider = provider; self.kind = kind; self.label = label
        self.plan = plan; self.windows = windows; self.updatedAt = updatedAt; self.error = error
    }
    public var pressure: Pressure { windows.map(\.pressure).max() ?? .unknown }
    public var tightestWindow: UsageWindow? {
        windows.filter { $0.usedPercent != nil }.max { ($0.usedPercent ?? 0) < ($1.usedPercent ?? 0) }
    }
    /// Stable subscription windows in the overview; reserves and scoped limits expand.
    public var overviewWindows: [UsageWindow] {
        let primary = windows.filter { $0.overviewEligible != false }
        if provider == .openai || provider == .claude {
            let session = primary.first { $0.durationMinutes == 300 || $0.id == "session" || $0.id == "five_hour" }
            let week = primary.first { $0.durationMinutes == 10_080 || $0.id == "weekly" || $0.id == "seven_day" }
            return [session ?? UsageWindow(id: "session-unreported", title: "5-hour session", usedPercent: nil, durationMinutes: 300),
                    week ?? UsageWindow(id: "week-unreported", title: "Weekly", usedPercent: nil, durationMinutes: 10_080)]
        }
        return Array(primary.prefix(2))
    }
    public func isStale(at now: Date = Date()) -> Bool {
        guard kind != .demo else { return false }
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > (kind == .manual ? 86_400 : 900)
            || windows.contains { $0.resetIsPast(at: now) }
    }
    public func reliablePressure(at now: Date = Date()) -> Pressure {
        error != nil || isStale(at: now) ? .unknown : pressure
    }
}

public enum SampleData {
    public static func accounts(at now: Date = Date()) -> [ProviderAccount] {
        [
            ProviderAccount(provider: .claude, kind: .demo, plan: "Max", windows: [
                UsageWindow(id: "session", title: "5-hour session", usedPercent: 28, durationMinutes: 300, resetsAt: now.addingTimeInterval(9_480)),
                UsageWindow(id: "weekly", title: "Weekly", usedPercent: 76, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(187_200))
            ], updatedAt: now),
            ProviderAccount(provider: .openai, kind: .demo, plan: "Pro", windows: [
                UsageWindow(id: "session", title: "5-hour session", usedPercent: 18, durationMinutes: 300, resetsAt: now.addingTimeInterval(13_800)),
                UsageWindow(id: "weekly", title: "Weekly", usedPercent: 37, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(367_200))
            ], updatedAt: now),
            ProviderAccount(provider: .grok, kind: .demo, plan: "SuperGrok", windows: [
                UsageWindow(id: "weekly", title: "Weekly", usedPercent: 9, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(359_000))
            ], updatedAt: now),
            ProviderAccount(provider: .grokBot, kind: .demo, plan: "SuperGrok", windows: [
                UsageWindow(id: "weekly", title: "Weekly", usedPercent: 43, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(187_200))
            ], updatedAt: now)
        ]
    }
}
