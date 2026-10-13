import Foundation

/// Decode only the documented account quota response. Never infer missing quota windows.
public enum CodexSnapshot {
    public static func windows(from data: Data) throws -> [UsageWindow] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let buckets: [(String, Bucket)]
        if let mapped = response.rateLimitsByLimitId, !mapped.isEmpty {
            let primaryID = response.rateLimits?.limitId ?? "codex"
            buckets = mapped.sorted {
                let leftMain = $0.key == primaryID || $0.value.limitId == primaryID
                let rightMain = $1.key == primaryID || $1.value.limitId == primaryID
                return leftMain == rightMain ? $0.key < $1.key : leftMain
            }
        } else if let legacy = response.rateLimits {
            buckets = [(legacy.limitId ?? "codex", legacy)]
        } else { return [] }
        return buckets.flatMap { key, bucket in
            [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { slot, window in
                guard let window else { return nil }
                let title = windowTitle(minutes: window.windowDurationMins)
                let primaryID = response.rateLimits?.limitId ?? "codex"
                let isMain = key == primaryID || bucket.limitId == primaryID
                let prefix = buckets.count > 1 && !isMain ? "\(bucket.limitName ?? key) · " : ""
                return UsageWindow(id: "\(key).\(slot)", title: prefix + title,
                    usedPercent: window.usedPercent, durationMinutes: window.windowDurationMins,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) }, overviewEligible: isMain)
            }
        }
    }
    public static func windowTitle(minutes: Int?) -> String {
        guard let minutes else { return "Usage" }
        switch minutes {
        case 10_080: return "Weekly"
        case 40_320...46_080: return "Monthly"
        case 1_440: return "Daily"
        case 1..<1_440: return minutes % 60 == 0 ? "\(minutes / 60)-hour session" : "\(minutes)-minute session"
        default: return "\(minutes)-minute window"
        }
    }
    private struct Response: Decodable {
        var rateLimits: Bucket?
        var rateLimitsByLimitId: [String: Bucket]?
    }
    private struct Bucket: Decodable {
        var limitId: String?
        var limitName: String?
        var primary: Window?
        var secondary: Window?
    }
    private struct Window: Decodable {
        var usedPercent: Double?
        var windowDurationMins: Int?
        var resetsAt: Double?
    }
}
