import Foundation
import Testing
@testable import LifePreserverCore

@Test func expiredRefreshGrantRequiresSignInInsteadOfRetrying() {
    let expired = Data(#"{"error":"invalid_grant","error_description":"Refresh token has expired"}"#.utf8)
    #expect(OAuthTokenFailure.requiresReconnect(status: 400, data: expired))
    #expect(OAuthTokenFailure.requiresReconnect(status: 401, data: expired))
    #expect(!OAuthTokenFailure.requiresReconnect(status: 500, data: expired))
    #expect(!OAuthTokenFailure.requiresReconnect(status: 400, data: Data(#"{"error":"invalid_request"}"#.utf8)))
    #expect(!OAuthTokenFailure.requiresReconnect(status: 400, data: Data("unreadable".utf8)))
}

@Test func usageIsClampedAndUnknownIsNotZero() {
    #expect(UsageWindow(id: "a", title: "Session", usedPercent: 123).remainingPercent == 0)
    #expect(UsageWindow(id: "a", title: "Session", usedPercent: -12).remainingPercent == 100)
    #expect(UsageWindow(id: "a", title: "Session", usedPercent: nil).remainingPercent == nil)
    #expect(UsageWindow(id: "a", title: "Session", usedPercent: .nan).pressure == .unknown)
    #expect(UsageWindow(id: "a", title: "Session", usedPercent: .infinity).remainingPercent == nil)
}

@Test func pressureBoundaries() {
    #expect(Pressure(usedPercent: 69.9) == .comfortable)
    #expect(Pressure(usedPercent: 70) == .watch)
    #expect(Pressure(usedPercent: 90) == .critical)
    #expect(Pressure(usedPercent: 100) == .exhausted)
    #expect(Pressure(usedPercent: nil) == .unknown)
}

@Test func tightestWindowControlsPressureInsteadOfAveraging() {
    let account = ProviderAccount(provider: .claude, kind: .manual, windows: [
        UsageWindow(id: "s", title: "Session", usedPercent: 2),
        UsageWindow(id: "w", title: "Weekly", usedPercent: 97)
    ], updatedAt: Date())
    #expect(account.pressure == .critical)
    #expect(account.tightestWindow?.remainingPercent == 3)
}

@Test func oldReadingsAndErrorsAreNeverHealthy() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    var account = ProviderAccount(provider: .openai, kind: .codex,
        windows: [UsageWindow(id: "s", title: "Session", usedPercent: 2)], updatedAt: now.addingTimeInterval(-901))
    #expect(account.isStale(at: now))
    #expect(account.reliablePressure(at: now) == .unknown)
    account.updatedAt = now; account.error = "Offline"
    #expect(account.reliablePressure(at: now) == .unknown)
    account.error = nil
    #expect(account.reliablePressure(at: now) == .comfortable)
}

@Test func passingAResetDoesNotInventAFullQuota() {
    let now = Date()
    let window = UsageWindow(id: "s", title: "Session", usedPercent: 100, resetsAt: now.addingTimeInterval(-1))
    let account = ProviderAccount(provider: .claude, kind: .manual, windows: [window], updatedAt: now)
    #expect(window.remainingPercent == 0)
    #expect(window.resetText(at: now) == "Awaiting new reading")
    #expect(account.isStale(at: now))
    #expect(account.reliablePressure(at: now) == .unknown)
}

@Test func manualReadingsHaveTheirOwnFreshnessPolicy() {
    let now = Date()
    let account = ProviderAccount(provider: .grok, kind: .manual, updatedAt: now.addingTimeInterval(-901))
    #expect(!account.isStale(at: now))
    #expect(account.isStale(at: now.addingTimeInterval(86_400)))
}

@Test func missingSessionDoesNotTurnWeeklyIntoSession() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1784246400},"secondary":null}}"#.utf8)
    let windows = try CodexSnapshot.windows(from: data)
    #expect(windows.count == 1)
    #expect(windows[0].title == "Weekly")
    #expect(windows[0].remainingPercent == 69)
    #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1784246400))
}

@Test func mappedBucketsTakePrecedenceWithoutDoubleCounting() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":76,"windowDurationMins":10080}},"extra":{"limitName":"Extra","primary":{"usedPercent":45,"windowDurationMins":60}}}}"#.utf8)
    let windows = try CodexSnapshot.windows(from: data)
    #expect(windows.count == 3)
    #expect(windows[0].title == "5-hour session")
    #expect(windows[2].title == "Extra · 1-hour session")
    #expect(Set(windows.map(\.id)).count == 3)
    #expect(!windows.contains { $0.usedPercent == 99 })
}

@Test func nullMetadataStaysUnknown() throws {
    let windows = try CodexSnapshot.windows(from: Data(#"{"rateLimits":{"primary":{"usedPercent":null,"resetsAt":null,"windowDurationMins":null}}}"#.utf8))
    #expect(windows.count == 1)
    #expect(windows[0].pressure == .unknown)
    #expect(windows[0].resetText() == "Reset not provided")
    #expect(try CodexSnapshot.windows(from: Data("{}".utf8)).isEmpty)
}

@Test func emptyMapFallsBackToLegacy() throws {
    let windows = try CodexSnapshot.windows(from: Data(#"{"rateLimitsByLimitId":{},"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}"#.utf8))
    #expect(windows.count == 1)
    #expect(windows[0].remainingPercent == 75)
}

@Test func malformedUsageFailsRatherThanLookingHealthy() {
    #expect(throws: (any Error).self) {
        try CodexSnapshot.windows(from: Data(#"{"rateLimits":{"primary":{"usedPercent":"unknown"}}}"#.utf8))
    }
}

@Test func localSnapshotRoundTripsWithoutCredentials() throws {
    let accounts = SampleData.accounts()
    let data = try JSONEncoder().encode(accounts)
    #expect(try JSONDecoder().decode([ProviderAccount].self, from: data) == accounts)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("access_token"))
    #expect(!json.contains("refresh_token"))
}

@Test func resetCountdownRoundsUp() {
    let now = Date()
    #expect(UsageWindow(id: "s", title: "Session", usedPercent: 10, resetsAt: now.addingTimeInterval(1)).resetText(at: now) == "Resets in 1m")
    #expect(UsageWindow(id: "s", title: "Session", usedPercent: 10, resetsAt: now.addingTimeInterval(7260)).resetText(at: now) == "Resets in 2h 1m")
}

@Test func reservePoolsCannotHideConstrainedWeeklyUsage() {
    let account = ProviderAccount(provider: .openai, kind: .codex, windows: [
        UsageWindow(id: "reserve", title: "Reserve", usedPercent: 0),
        UsageWindow(id: "session", title: "Session", usedPercent: 80),
        UsageWindow(id: "weekly", title: "Weekly", usedPercent: 92)
    ])
    #expect(account.overviewWindows.map(\.id) == ["session", "weekly"])
}

@Test func unknownReserveCannotReplaceMainSession() {
    let account = ProviderAccount(provider: .openai, kind: .codex, windows: [
        UsageWindow(id: "reserve", title: "Reserve", usedPercent: nil),
        UsageWindow(id: "session", title: "Session", usedPercent: 2),
        UsageWindow(id: "weekly", title: "Weekly", usedPercent: 92)
    ])
    #expect(account.overviewWindows.map(\.id) == ["session", "weekly"])
}

@Test func mainWindowsKeepTheirPositionsAndNeverUseReserveAsSession() throws {
    let data = Data(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":16,"windowDurationMins":10080}},"gpt-reserve":{"primary":{"usedPercent":0,"windowDurationMins":10080}}}}"#.utf8)
    let account = ProviderAccount(provider:.openai, kind:.codex, windows:try CodexSnapshot.windows(from:data))
    #expect(account.overviewWindows.map(\.title) == ["5-hour session", "Weekly"])
    #expect(account.overviewWindows[0].usedPercent == nil)
    #expect(account.overviewWindows[1].remainingPercent == 84)
}

@Test func claudeKeepsSubscriptionWindowsAndExcludesSpend() throws {
    let data = Data(#"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":92,"resets_at":"2026-09-15T12:00:00.000Z"},"seven_day_sonnet":{"utilization":100},"extra_usage":{"utilization":100,"used_credits":5000}}"#.utf8)
    let windows = try SubscriptionSnapshot.claude(data)
    #expect(windows.count == 3)
    #expect(windows[0].remainingPercent == 100)
    #expect(windows[1].resetsAt == SubscriptionSnapshot.date("2026-09-15T12:00:00Z"))
    let account = ProviderAccount(provider:.claude, kind:.claudeOAuth, windows:windows)
    #expect(account.overviewWindows.map(\.remainingPercent) == [100,8])
}

@Test func claudeMissingAndInvalidValuesRemainUnknown() throws {
    let windows = try SubscriptionSnapshot.claude(Data(#"{"five_hour":{"utilization":true},"seven_day":{"utilization":"42"}}"#.utf8))
    #expect(windows.allSatisfy { $0.usedPercent == nil })
    #expect(try SubscriptionSnapshot.claude(Data(#"{"five_hour":null}"#.utf8)).isEmpty)
}

@Test func grokUsesIncludedQuotaAndPeriodNotOnDemandSpending() throws {
    let windows = try SubscriptionSnapshot.grok(Data(#"{"config":{"creditUsagePercent":28,"onDemandUsed":99,"onDemandCap":100,"currentPeriod":{"start":"2026-09-08T00:00:00Z","end":"2026-09-15T00:00:00Z"}}}"#.utf8))
    #expect(windows.count == 1)
    #expect(windows[0].remainingPercent == 72)
    #expect(windows[0].durationMinutes == 10080)
    #expect(windows[0].title == "Weekly")
    let missing = try SubscriptionSnapshot.grok(Data(#"{"config":{"onDemandUsed":0,"onDemandCap":100}}"#.utf8))
    #expect(missing[0].remainingPercent == nil)
    let zero = try SubscriptionSnapshot.grok(Data(#"{"config":{"creditUsagePercent":0}}"#.utf8))
    #expect(zero[0].remainingPercent == 100)
}

private func protobufVarint(_ input: UInt64) -> [UInt8] {
    var value=input, result:[UInt8]=[]
    repeat { let byte=UInt8(value & 127); value >>= 7; result.append(byte | (value > 0 ? 128 : 0)) } while value > 0
    return result
}
private func protobufMessage(_ field: UInt8, _ bytes:[UInt8]) -> [UInt8] { [field*8+2] + protobufVarint(UInt64(bytes.count)) + bytes }
private func grpcFrame(_ bytes:[UInt8], flag:UInt8=0) -> Data {
    let n=UInt32(bytes.count)
    return Data([flag,UInt8(truncatingIfNeeded:n>>24),UInt8(truncatingIfNeeded:n>>16),UInt8(truncatingIfNeeded:n>>8),UInt8(truncatingIfNeeded:n)] + bytes)
}
@Test func grokProtobufDecodesSubscriptionPercentAndRejectsErrorTrailers() throws {
    let bits=Float(37).bitPattern
    let percent:[UInt8]=[13,UInt8(truncatingIfNeeded:bits),UInt8(truncatingIfNeeded:bits>>8),UInt8(truncatingIfNeeded:bits>>16),UInt8(truncatingIfNeeded:bits>>24)]
    let payload=grpcFrame(protobufMessage(1,percent))
    #expect(try GrokWireSnapshot.window(payload).remainingPercent == 63)
    let denied=payload+grpcFrame(Array("grpc-status: 16\r\n".utf8),flag:128)
    #expect(throws:(any Error).self) { try GrokWireSnapshot.window(denied) }
    #expect(throws:(any Error).self) { try GrokWireSnapshot.window(Data([0,0,0,0,255])) }
    #expect(throws:(any Error).self) { try GrokWireSnapshot.window(grpcFrame([10,255,255,255,255,255,255,255,255,255,255])) }
}
@Test func omittedGrokScalarOnlyMeansZeroWithAValidActivePeriod() throws {
    let now=Date(timeIntervalSince1970:1_800_000_000)
    let start=protobufMessage(2,[8]+protobufVarint(1_799_900_000))
    let end=protobufMessage(3,[8]+protobufVarint(1_800_504_800))
    let period=protobufMessage(8,[8,2]+start+end)
    let payload=grpcFrame(protobufMessage(1,period))
    #expect(try GrokWireSnapshot.window(payload,now:now).remainingPercent == 100)
    #expect(throws:(any Error).self) { try GrokWireSnapshot.window(payload,now:now.addingTimeInterval(1_000_000)) }
    #expect(throws:(any Error).self) { try GrokWireSnapshot.window(grpcFrame(protobufMessage(1,[])),now:now) }
}

@Test func grokBotIsAnIndependentIncludedWeeklyAllowance() throws {
    let data=Data(#"{"usagePercent":61,"hasNonZeroIncludedLimit":true,"usesPooledEnterpriseAllowance":false,"nextResetTimestampUtc":"2026-09-16T10:00:00Z","onDemandUsed":100}"#.utf8)
    let windows=try SubscriptionSnapshot.grokBot(data)
    #expect(windows.count == 1)
    #expect(windows[0].remainingPercent == 39)
    #expect(windows[0].durationMinutes == 10080)
    #expect(windows[0].resetsAt == SubscriptionSnapshot.date("2026-09-16T10:00:00Z"))
    #expect(Provider.grokBot != Provider.grok)
    #expect(try SubscriptionSnapshot.grokBot(Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":false}"#.utf8)).isEmpty)
    #expect(try SubscriptionSnapshot.grokBot(Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":true,"usesPooledEnterpriseAllowance":true}"#.utf8)).isEmpty)
    #expect(try SubscriptionSnapshot.grokBot(Data(#"{"hasNonZeroIncludedLimit":true}"#.utf8))[0].remainingPercent == nil)
}
