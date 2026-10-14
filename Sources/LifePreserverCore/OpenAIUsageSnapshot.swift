import Foundation

/// Direct WHAM response. Subscription windows only; API/on-demand credits are excluded.
public enum OpenAIUsageSnapshot {
    public static func parse(_ data: Data, at now: Date = Date()) throws -> (String?, [UsageWindow]) {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var windows = decode(response.rate_limit, prefix: "codex", title: "", main: true, at: now)
        for extra in response.additional_rate_limits ?? [] {
            guard let id = extra.limit_id ?? extra.metered_feature else { continue }
            windows += decode(extra.rate_limit, prefix: id, title: (extra.limit_name ?? id) + " · ", main: false, at: now)
        }
        return (response.plan_type?.capitalized, windows)
    }
    private static func decode(_ limit: Limit?, prefix: String, title: String, main: Bool, at now: Date) -> [UsageWindow] {
        guard let limit else { return [] }
        return [("primary", limit.primary_window), ("secondary", limit.secondary_window)].compactMap { slot, window in
            guard let window else { return nil }
            let minutes = window.limit_window_seconds.map { $0 / 60 }
            return UsageWindow(id: prefix + "." + slot, title: title + CodexSnapshot.windowTitle(minutes: minutes),
                usedPercent: window.used_percent, durationMinutes: minutes,
                resetsAt: window.reset_at.map { Date(timeIntervalSince1970: $0) }
                    ?? window.reset_after_seconds.map { now.addingTimeInterval($0) }, overviewEligible: main)
        }
    }
    private struct Response: Decodable { var plan_type: String?; var rate_limit: Limit?; var additional_rate_limits: [Extra]? }
    private struct Extra: Decodable { var limit_id: String?; var limit_name: String?; var metered_feature: String?; var rate_limit: Limit? }
    private struct Limit: Decodable { var primary_window: Window?; var secondary_window: Window? }
    private struct Window: Decodable { var used_percent: Double?; var limit_window_seconds: Int?; var reset_at: Double?; var reset_after_seconds: Double? }
}
