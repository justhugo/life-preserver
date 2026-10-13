import Foundation
import CoreFoundation

public enum SubscriptionSnapshot {
    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }

    public static func claude(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []
        let keys = [("five_hour", "5-hour session", 300), ("seven_day", "Weekly", 10_080),
                    ("seven_day_sonnet", "Sonnet · Weekly", 10_080), ("seven_day_opus", "Opus · Weekly", 10_080)]
        for (id, title, duration) in keys {
            guard let window = root[id] as? [String: Any] else { continue }
            windows.append(UsageWindow(id: id, title: title, usedPercent: number(window["utilization"]),
                durationMinutes: duration, resetsAt: date(window["resets_at"] as? String),
                overviewEligible: id == "five_hour" || id == "seven_day"))
        }
        for (index, item) in ((root["limits"] as? [[String: Any]]) ?? []).enumerated() {
            guard item["kind"] as? String == "weekly_scoped", item["is_active"] as? Bool != false else { continue }
            let scope = item["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let name = model?["display_name"] as? String ?? "Model"
            windows.append(UsageWindow(id: "scoped-\(index)", title: "\(name) · Weekly", usedPercent: number(item["percent"]),
                durationMinutes: 10_080, resetsAt: date(item["resets_at"] as? String), overviewEligible: false))
        }
        return windows
    }

    /// Only the included subscription pool. On-demand/API spending is deliberately ignored.
    public static func grok(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let config = root["config"] as? [String: Any] else { return [] }
        let period = config["currentPeriod"] as? [String: Any]
        let start = date(period?["start"] as? String)
        let end = date(period?["end"] as? String ?? config["billingPeriodEnd"] as? String)
        let duration = start.flatMap { start in end.map { Int($0.timeIntervalSince(start) / 60) } }
        let title = duration.map { $0 > 20_000 ? "Monthly" : "Weekly" } ?? "Weekly"
        return [UsageWindow(id: "grok-subscription", title: title, usedPercent: number(config["creditUsagePercent"]),
            durationMinutes: duration, resetsAt: end)]
    }

    public static func grokBot(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        // Enterprise pooled spend and trial credits are not a personal subscription allowance.
        guard root["hasNonZeroIncludedLimit"] as? Bool == true,
              root["usesPooledEnterpriseAllowance"] as? Bool != true else { return [] }
        return [UsageWindow(id: "grok-bot-weekly", title: "Weekly", usedPercent: number(root["usagePercent"]),
            durationMinutes: 10_080, resetsAt: date(root["nextResetTimestampUtc"] as? String))]
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { return value.doubleValue }
        return nil
    }
}
