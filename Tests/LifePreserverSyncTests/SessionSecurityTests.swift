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
}
