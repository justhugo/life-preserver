import CloudKit
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

/// Credentials are encrypted before CloudKit sees them. Shared Keychain holds only
/// encryption keys; CloudKit CAS leases serialize rotating-token exchanges.
@MainActor
public final class SharedProviderSessions {
    public static let shared = SharedProviderSessions()
    private let cloud = PrivateUsageCloud()
    private var database: CKDatabase { CKContainer(identifier: PrivateUsageCloud.containerIdentifier).privateCloudDatabase }
    private let directoryID = CKRecord.ID(recordName: "provider-directory-v1")
    private var deviceID: String {
        if let value = UserDefaults.standard.string(forKey: "sessionRenewalDeviceID") { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: "sessionRenewalDeviceID"); return value
    }
    public init() {}
    public func ownerID() async throws -> String { try await cloud.ownerID() }
    private func id(_ account: UUID) -> CKRecord.ID { CKRecord.ID(recordName: "provider-session-v1-" + account.uuidString) }
    private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
        do { return try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }
    @discardableResult private func save(_ record: CKRecord) async throws -> CKRecord {
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = result.saveResults[record.recordID] else { throw SessionSharingError.invalidSession }
        return try saved.get()
    }
    public func accounts() async throws -> [SharedProviderAccount] {
        guard let record = try await fetch(directoryID), let data = record["accounts"] as? Data else { return [] }
        return try JSONDecoder().decode([SharedProviderAccount].self, from: data)
    }
    public func setAccounts(_ accounts: [SharedProviderAccount]) async throws {
        let bytes = try JSONEncoder().encode(accounts.sorted { $0.id.uuidString < $1.id.uuidString })
        for _ in 0..<4 {
            let record = try await fetch(directoryID) ?? CKRecord(recordType: "ProviderDirectoryV1", recordID: directoryID)
            if record["accounts"] as? Data == bytes { return }
            record["accounts"] = bytes
            do { try await save(record); return }
            catch let error as CKError where error.code == .serverRecordChanged { continue }
        }
        throw SessionSharingError.changed
    }
    public func contains(_ account: UUID) async throws -> Bool { try await fetch(id(account)) != nil }
    public func currentCredential(for account: SharedProviderAccount) async throws -> SubscriptionCredential {
        let owner = try await ownerID()
        guard let record = try await fetch(id(account.id)) else { throw SessionSharingError.unavailable }
        guard record["leaseOwner"] == nil else { throw SessionSharingError.renewing }
        return try decrypt(record, account: account, owner: owner)
    }
    public func share(_ credential: SubscriptionCredential, account: SharedProviderAccount, expectedOwner: String, replacing: Bool = false) async throws {
        let owner = try await ownerID()
        guard owner == expectedOwner else { throw SessionSharingError.changed }
        let existing = try await fetch(id(account.id))
        if existing != nil && !replacing { return }
        let record = existing ?? CKRecord(recordType: "ProviderSessionV1", recordID: id(account.id))
        let keyID = UUID().uuidString
        let key = try SharedSessionKeychain.key(owner: owner, id: keyID, create: true)
        record["provider"] = account.provider.rawValue; record["keyID"] = keyID
        record["revision"] = UUID().uuidString
        record["leaseOwner"] = nil; record["leaseUntil"] = nil
        record["payload"] = try SessionEncryption.seal(credential, key: key, context: context(record))
        do { try await save(record) }
        catch let error as CKError where error.code == .serverRecordChanged && !replacing {
            // Another device seeded the same account first. Never overwrite its rotated session.
            guard try await contains(account.id) else { throw error }
        }
    }
    private func context(_ record: CKRecord) throws -> String {
        guard let provider = record["provider"] as? String, Provider(rawValue: provider) != nil,
              let key = record["keyID"] as? String, UUID(uuidString: key) != nil,
              let revision = record["revision"] as? String, UUID(uuidString: revision) != nil else { throw SessionSharingError.invalidSession }
        return "LifePreserver/session/v1|\(record.recordID.recordName)|\(provider)|\(key)|\(revision)"
    }
    private func decrypt(_ record: CKRecord, account: SharedProviderAccount, owner: String) throws -> SubscriptionCredential {
        guard record["provider"] as? String == account.provider.rawValue,
              let keyID = record["keyID"] as? String, let bytes = record["payload"] as? Data else { throw SessionSharingError.invalidSession }
        let key = try SharedSessionKeychain.key(owner: owner, id: keyID)
        return try SessionEncryption.open(bytes, key: key, context: context(record))
    }
    private struct PendingRenewal: Codable {
        let revision: String
        let credential: SubscriptionCredential
    }
    /// A failed save must never discard a successfully rotated refresh token.
    /// A local Keychain journal lets this device complete the same transaction later.
    private func complete(_ pending: PendingRenewal, record: CKRecord, owner: String, journal: String) async throws -> SubscriptionCredential {
        var current = record
        for _ in 0..<4 {
            guard current["revision"] as? String == pending.revision,
                  current["leaseOwner"] as? String == deviceID,
                  let keyID = current["keyID"] as? String else {
                try SharedSessionKeychain.remove(journal, sync: false)
                throw SessionSharingError.changed
            }
            let key = try SharedSessionKeychain.key(owner: owner, id: keyID)
            current["revision"] = UUID().uuidString
            current["payload"] = try SessionEncryption.seal(pending.credential, key: key, context: context(current))
            current["leaseOwner"] = nil; current["leaseUntil"] = nil
            do {
                try await save(current)
                try SharedSessionKeychain.remove(journal, sync: false)
                return pending.credential
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard let next = try await fetch(record.recordID) else { throw SessionSharingError.unavailable }
                current = next
            }
        }
        throw SessionSharingError.changed
    }
    public func credential(for account: SharedProviderAccount, rejectedToken: String? = nil,
                           renew: @escaping (SubscriptionCredential) async throws -> SubscriptionCredential) async throws -> SubscriptionCredential {
        let owner = try await ownerID()
        let journal = "pending|\(owner)|\(account.id.uuidString)"
        for attempt in 0..<20 {
            try Task.checkCancellation()
            guard var record = try await fetch(id(account.id)) else { throw SessionSharingError.unavailable }
            if let data = try SharedSessionKeychain.read(journal, sync: false) {
                let pending = try JSONDecoder().decode(PendingRenewal.self, from: data)
                if record["leaseOwner"] as? String == deviceID, record["revision"] as? String == pending.revision {
                    return try await complete(pending, record: record, owner: owner, journal: journal)
                }
                try SharedSessionKeychain.remove(journal, sync: false)
            }
            let credential = try decrypt(record, account: account, owner: owner)
            let decision = SessionRenewalDecision.evaluate(credential: credential, rejectedToken: rejectedToken,
                leaseOwner: record["leaseOwner"] as? String, leaseUntil: record["leaseUntil"] as? Date, at: Date())
            switch decision {
            case .useCurrent: return credential
            case .wait:
                guard attempt < 19 else { throw SessionSharingError.renewing }
                try await Task.sleep(for: .seconds(1)); continue
            case .recover: throw SessionSharingError.interrupted
            case .acquireLease: break
            }
            record["leaseOwner"] = deviceID; record["leaseUntil"] = Date().addingTimeInterval(90)
            do { record = try await save(record) }
            catch let error as CKError where error.code == .serverRecordChanged { continue }
            // After acquiring a lease, do not cancel between token exchange and durable
            // journal/save. A timeout or crash retains the lease and fails closed: other
            // devices must not blindly reuse a possibly consumed refresh token.
            let leasedRecord = record
            let transaction = Task { @MainActor in
                #if canImport(UIKit)
                let background = UIApplication.shared.beginBackgroundTask(withName: "Finish sign-in renewal")
                defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
                #endif
                let fresh = try await renew(credential)
                guard let revision = leasedRecord["revision"] as? String else { throw SessionSharingError.invalidSession }
                let pending = PendingRenewal(revision: revision, credential: fresh)
                try SharedSessionKeychain.write(JSONEncoder().encode(pending), account: journal, sync: false)
                return try await self.complete(pending, record: leasedRecord, owner: owner, journal: journal)
            }
            return try await transaction.value
        }
        throw SessionSharingError.renewing
    }
    public func remove(_ account: UUID) async throws {
        let result = try await database.modifyRecords(saving: [], deleting: [id(account)], atomically: true)
        if let deleted = result.deleteResults[id(account)] {
            do { try deleted.get() }
            catch let error as CKError where error.code == .unknownItem { return }
        }
    }
}
