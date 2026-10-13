import CloudKit
import Foundation
import Testing
import LifePreserverCore
@testable import LifePreserverSync

@Test func cloudFailuresDoNotAllClaimThePhoneIsOffline() {
    #expect(PrivateUsageCloud.message(for: CKError(.networkUnavailable)).contains("Wi-Fi"))
    #expect(PrivateUsageCloud.message(for: CKError(.serviceUnavailable)).contains("shortly"))
    #expect(PrivateUsageCloud.message(for: CKError(.accountTemporarilyUnavailable)).contains("account"))
    #expect(PrivateUsageCloud.message(for: CKError(.requestRateLimited)).contains("wait"))
    #expect(PrivateUsageCloud.message(for: CKError(.missingEntitlement)).contains("setup"))
    #expect(PrivateUsageCloud.message(for: MobileSnapshot.SnapshotError.unsupported).contains("Update"))
}

@Test func cancellationIsNotAConnectionFailure() {
    #expect(PrivateUsageCloud.isCancellation(CancellationError()))
    #expect(PrivateUsageCloud.isCancellation(CKError(.operationCancelled)))
    #expect(PrivateUsageCloud.isCancellation(URLError(.cancelled)))
    #expect(!PrivateUsageCloud.isCancellation(CKError(.networkFailure)))
}

@Test func cloudDiagnosticsExcludePrivateErrorContents() {
    let error = NSError(domain: CKErrorDomain, code: CKError.Code.networkFailure.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "PRIVATE DATA", "access_token": "PRIVATE TOKEN"])
    let diagnostic = PrivateUsageCloud.diagnosticCode(for: error)
    #expect(diagnostic == "\(CKErrorDomain):4")
    #expect(!diagnostic.contains("PRIVATE"))
}
