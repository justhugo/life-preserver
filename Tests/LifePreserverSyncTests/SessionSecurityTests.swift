import CryptoKit
import XCTest
import LifePreserverCore
@testable import LifePreserverSync

final class SessionSecurityTests: XCTestCase {
    func testCredentialEnvelopeRejectsTamperingAndWrongAccount() throws {
        let key = SymmetricKey(size: .bits256)
        let credential = SubscriptionCredential(accessToken: "test-access-secret", refreshToken: "test-refresh-secret")
        let context = "session|account-a|claude|key-a|revision-a"
        let sealed = try SessionEncryption.seal(credential, key: key, context: context)
        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains(credential.accessToken))
        XCTAssertEqual(try SessionEncryption.open(sealed, key: key, context: context), credential)
        XCTAssertThrowsError(try SessionEncryption.open(sealed, key: key, context: "session|account-b|claude|key-a|revision-a"))
        XCTAssertThrowsError(try SessionEncryption.open(sealed, key: SymmetricKey(size: .bits256), context: context))
        var tampered = sealed; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try SessionEncryption.open(tampered, key: key, context: context))
    }
    func testRotatingRefreshTokenRequiresExclusiveLease() {
        let now = Date()
        let expired = SubscriptionCredential(accessToken: "expired", refreshToken: "rotating", expiresAt: now)
        XCTAssertEqual(SessionRenewalDecision.evaluate(credential: expired, rejectedToken: nil, leaseOwner: nil, leaseUntil: nil, at: now), .acquireLease)
        XCTAssertEqual(SessionRenewalDecision.evaluate(credential: expired, rejectedToken: nil, leaseOwner: "phone", leaseUntil: now.addingTimeInterval(90), at: now), .wait)
        // An expired lease could represent a consumed refresh token: never steal/retry it.
        XCTAssertEqual(SessionRenewalDecision.evaluate(credential: expired, rejectedToken: nil, leaseOwner: "phone", leaseUntil: now.addingTimeInterval(-1), at: now), .recover)
    }
    func testSimultaneousUnauthorizedResponseUsesAlreadyRenewedToken() {
        let now = Date()
        let fresh = SubscriptionCredential(accessToken: "new-token", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(SessionRenewalDecision.evaluate(credential: fresh, rejectedToken: "old-token", leaseOwner: nil, leaseUntil: nil, at: now), .useCurrent)
        XCTAssertEqual(SessionRenewalDecision.evaluate(credential: fresh, rejectedToken: "new-token", leaseOwner: nil, leaseUntil: nil, at: now), .acquireLease)
    }

    func testRenewalOriginOnlyNamesTheRemoteOwnerOfTheCurrentLease() throws {
        let original = SessionRenewalOrigin(owner: "tablet", revision: "session", label: "  Living Room\niPad  ")
        let origin = try JSONDecoder().decode(SessionRenewalOrigin.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(origin.recoveryLabel(leaseOwner: "tablet", revision: "session", localOwner: "phone"), "Living Room iPad")
        XCTAssertNil(origin.recoveryLabel(leaseOwner: "tablet", revision: "session", localOwner: "tablet"))
        XCTAssertNil(origin.recoveryLabel(leaseOwner: "phone", revision: "session", localOwner: "mac"))
        XCTAssertNil(origin.recoveryLabel(leaseOwner: "tablet", revision: "reconnected", localOwner: "mac"))
        XCTAssertNil(origin.recoveryLabel(leaseOwner: nil, revision: "session", localOwner: "mac"))
    }

    func testInterruptedRenewalProvidesMacRecoveryWithOrWithoutADeviceLabel() {
        let named = SessionSharingError.interrupted(device: "Living Room iPad").localizedDescription
        let unnamed = SessionSharingError.interrupted(device: nil).localizedDescription
        XCTAssertTrue(named.contains("Living Room iPad"))
        XCTAssertTrue(named.contains("Settings → Accounts"))
        XCTAssertTrue(unnamed.contains("Settings → Accounts"))
        XCTAssertFalse(unnamed.contains("Open Life Preserver there"))
    }
}
