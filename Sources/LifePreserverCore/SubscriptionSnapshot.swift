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

    public static func grok(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let config = root["config"] as? [String: Any] else { return [] }
        let period = config["currentPeriod"] as? [String: Any]
        let start = date(period?["start"] as? String)
        let end = date(period?["end"] as? String ?? config["billingPeriodEnd"] as? String)
        let duration = start.flatMap { start in end.map { Int($0.timeIntervalSince(start) / 60) } }
        let title = duration.map { $0 > 20_000 ? "Monthly" : "Weekly" } ?? "Weekly"
        let used = number(config["creditUsagePercent"])
        // The binary fallback can supply the included percentage if the JSON response omitted it.
        let sharedStart = bool(config["isUnifiedBillingUser"]) == true ? start : nil
        let billing = (used ?? 100) >= 100 ? grokBilling(config, onDemandEnabled: bool(root["onDemandEnabled"]), sharedStart: sharedStart) : nil
        return [UsageWindow(id: "grok-subscription", title: title, usedPercent: used,
            durationMinutes: duration, resetsAt: end, extraUsage: billing)]
    }

    public static func grokBot(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        // Enterprise pooled spend and trial credits are not a personal subscription allowance.
        guard root["hasNonZeroIncludedLimit"] as? Bool == true,
              root["usesPooledEnterpriseAllowance"] as? Bool != true else { return [] }
        let used = number(root["usagePercent"])
        let billing = (used ?? 0) >= 100 ? grokBotBilling(root) : nil
        return [UsageWindow(id: "grok-bot-weekly", title: "Weekly", usedPercent: used,
            durationMinutes: 10_080, resetsAt: date(root["nextResetTimestampUtc"] as? String), extraUsage: billing)]
    }

    private static func grokBilling(_ config: [String: Any], onDemandEnabled: Bool?, sharedStart: Date?) -> ExtraUsageStatus? {
        let monthly = monthlySpending(used: grokCents(config["onDemandUsed"]), limit: grokCents(config["onDemandCap"]))
        let limitReached = monthly?.remainingCents == 0
        let balance = grokCents(config["prepaidBalance"])
        if balance != nil || sharedStart != nil || (limitReached && onDemandEnabled == nil) {
            return .prepaid(balanceCents: balance, spendingLimitReached: limitReached, monthly: monthly, sharedPeriodStart: sharedStart)
        }
        return onDemandEnabled.map { .onDemand(enabled: $0, spendingLimitReached: $0 && limitReached) }
    }

    private static func grokBotBilling(_ root: [String: Any]) -> ExtraUsageStatus? {
        if bool(root["isUnified"]) == true {
            guard root["billingBrand"] as? String == "SAND_BILLING_BRAND_GROK" else { return nil }
            return .prepaid(balanceCents: cents(root["prepaidAvailableCents"]), spendingLimitReached: false,
                sharedPeriodStart: date(root["currentPeriodStart"] as? String))
        }
        guard let settings = root["onDemandSettings"] as? [String: Any],
              bool(settings["visible"]) != false, bool(settings["eligible"]) != false,
              let enabled = bool(settings["enabled"]) else { return nil }
        return .onDemand(enabled: enabled, spendingLimitReached: false)
    }

    public static func cursorOnDemandLimitReached(_ data: Data, at now: Date = Date()) throws -> Bool {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard root["limitType"] as? String == "user",
              let end = date(root["billingCycleEnd"] as? String), end > now,
              let individual = root["individualUsage"] as? [String: Any],
              let onDemand = individual["onDemand"] as? [String: Any], bool(onDemand["enabled"]) == true else { return false }
        return monthlySpending(used: cents(onDemand["used"]), limit: cents(onDemand["limit"]))?.remainingCents == 0
    }

    public static func grokBotMonthlySpending(prepaid: Data, periodUsage: Data) throws -> ExtraUsageStatus.MonthlySpending? {
        let prepaid = try JSONSerialization.jsonObject(with: prepaid) as? [String: Any]
        let period = try JSONSerialization.jsonObject(with: periodUsage) as? [String: Any]
        guard let limits = period?["spendLimitUsage"] as? [String: Any], limits["limitType"] as? String == "user" else { return nil }
        // Unified accounts report the weekly quota in GetCurrentPeriodUsage. The monthly
        // spend comes from the prepaid wallet; the legacy remaining field can be unchanged.
        return monthlySpending(used: cents(prepaid?["spentThisMonthCents"]), limit: cents(limits["individualLimit"]))
    }

    private static func monthlySpending(used: Int?, limit: Int?) -> ExtraUsageStatus.MonthlySpending? {
        guard let used, let limit, limit > 0 else { return nil }
        return .init(usedCents: used, limitCents: limit)
    }

    private static func grokCents(_ value: Any?) -> Int? {
        guard let amount = value as? [String: Any] else { return nil }
        // An empty Cent message represents an explicit zero in proto3 JSON.
        return amount.isEmpty ? 0 : cents(amount["val"])
    }

    private static func cents(_ value: Any?) -> Int? {
        let amount = (value as? String).flatMap { Int($0) } ?? number(value).flatMap { Int(exactly: $0) }
        guard let amount, amount >= 0 else { return nil }
        return amount
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { return value.doubleValue }
        return nil
    }
}
