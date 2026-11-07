import CryptoKit
import Foundation
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

public enum SessionEncryption {
    public static func seal(_ credential: SubscriptionCredential, key: SymmetricKey, context: String) throws -> Data {
        let clear = try JSONEncoder().encode(credential)
        return try AES.GCM.seal(clear, using: key, authenticating: Data(context.utf8)).combined!
    }
    public static func open(_ data: Data, key: SymmetricKey, context: String) throws -> SubscriptionCredential {
        guard data.count < 262_144 else { throw SessionSharingError.invalidSession }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: Data(context.utf8))
        let credential = try JSONDecoder().decode(SubscriptionCredential.self, from: clear)
        guard !credential.accessToken.isEmpty else { throw SessionSharingError.invalidSession }
        return credential
    }
}

public enum SessionSharingError: LocalizedError {
    case keyPending, invalidSession, unavailable, renewing, pendingSync, changed
    case interrupted(device: String?)
    public var errorDescription: String? {
        switch self {
        case .keyPending: return "Waiting for your secure sign-in key. Turn on iCloud Passwords & Keychain on both devices, then refresh."
        case .invalidSession: return "The shared sign-in couldn’t be verified. Reconnect this provider."
        case .unavailable: return "This provider isn’t connected for direct checks yet. Open Life Preserver on your Mac once to finish setup."
        case .renewing: return "Another device is renewing this sign-in. Try refreshing again shortly."
        case .pendingSync:
            return "The renewed sign-in is saved on this device. Refresh here when you’re online to finish syncing it."
        case .interrupted(let device):
            let reconnect = "reconnect this provider in Life Preserver → Settings → Accounts on your Mac."
            guard let device else { return "Sign-in renewal didn’t finish. To restore usage checks, \(reconnect)" }
            return "Sign-in renewal started on \(device). Open Life Preserver there and refresh to see if it can finish. If the warning stays, \(reconnect)"
        case .changed: return "The sign-in changed on another device. Refresh to use the new connection."
        }
    }
}

struct SessionRenewalOrigin: Codable {
    let owner: String
    let revision: String
    let label: String

    static func cleanLabel(_ label: String) -> String {
        String(label.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(48))
    }

    func recoveryLabel(leaseOwner: String?, revision: String?, localOwner: String) -> String? {
        guard leaseOwner == owner, revision == self.revision, owner != localOwner else { return nil }
        let label = Self.cleanLabel(label)
        return label.isEmpty ? nil : label
    }
}

public enum SessionRenewalDecision: Equatable {
    case useCurrent, acquireLease, wait, recover
    public static func evaluate(credential: SubscriptionCredential, rejectedToken: String?, leaseOwner: String?,
                                leaseUntil: Date?, at now: Date) -> Self {
        let expired = credential.expiresAt.map { $0 <= now.addingTimeInterval(120) } ?? false
        // A simultaneous reader may already have replaced the rejected bearer.
        let rejected = rejectedToken.map { $0 == credential.accessToken } ?? false
        guard expired || rejected else { return .useCurrent }
        if let owner = leaseOwner, !owner.isEmpty {
            return leaseUntil.map { $0 > now } == true ? .wait : .recover
        }
        return .acquireLease
    }
}
