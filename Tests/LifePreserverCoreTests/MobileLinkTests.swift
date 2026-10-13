import Foundation
import Testing
@testable import LifePreserverCore

@Test func linkHealthRequiresBothACloudCheckAndARecentMacPublication() {
    let now = Date()
    let fresh = MobileSnapshot(accounts: [], sharingEnabled: true, at: now)
    let old = MobileSnapshot(accounts: [], sharingEnabled: true, at: now.addingTimeInterval(-901))
    #expect(MobileLinkState.evaluate(snapshot: fresh, lastChecked: now, checkFailed: false, at: now) == .healthy)
    #expect(MobileLinkState.evaluate(snapshot: old, lastChecked: now, checkFailed: false, at: now) == .stale)
    #expect(MobileLinkState.evaluate(snapshot: fresh, lastChecked: now, checkFailed: true, at: now) == .failed)
    #expect(MobileLinkState.evaluate(snapshot: fresh, lastChecked: nil, checkFailed: false, at: now) == .unchecked)
}

@Test func sharingOffAndNoSnapshotAreNotShownAsHealthy() {
    let now = Date()
    let off = MobileSnapshot(accounts: [], sharingEnabled: false, at: now)
    #expect(MobileLinkState.evaluate(snapshot: off, lastChecked: now, checkFailed: false, at: now) == .sharingOff)
    #expect(MobileLinkState.evaluate(snapshot: nil, lastChecked: now, checkFailed: false, at: now) == .waiting)
}
