import XCTest
@testable import LifePreserverCore

final class OpenAIUsageTests: XCTestCase {
    func testDirectWindowsAndExtraPoolsStaySeparate() throws {
        let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":21,"limit_window_seconds":18000,"reset_at":2000000000},"secondary_window":{"used_percent":64,"limit_window_seconds":604800,"reset_after_seconds":200}},"additional_rate_limits":[{"limit_id":"spark","limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":95,"limit_window_seconds":18000}}}],"credits":{"balance":1000}}"#.utf8)
        let now = Date(timeIntervalSince1970: 1000)
        let (plan, windows) = try OpenAIUsageSnapshot.parse(data, at: now)
        XCTAssertEqual(plan, "Pro")
        XCTAssertEqual(windows.count, 3)
        let account = ProviderAccount(provider: .openai, kind: .codex, windows: windows)
        XCTAssertEqual(account.overviewWindows.map(\.usedPercent), [21, 64])
        XCTAssertEqual(windows[1].resetsAt, now.addingTimeInterval(200))
        XCTAssertFalse(windows[2].overviewEligible!)
    }
    func testMissingUsageIsNeverInventedFromCredits() throws {
        let (_, windows) = try OpenAIUsageSnapshot.parse(Data(#"{"credits":{"balance":20},"rate_limit":{"primary_window":{"limit_window_seconds":18000}}}"#.utf8))
        XCTAssertEqual(windows.count, 1)
        XCTAssertNil(windows[0].usedPercent)
        XCTAssertTrue(try OpenAIUsageSnapshot.parse(Data(#"{"plan_type":"pro"}"#.utf8)).1.isEmpty)
    }
}
