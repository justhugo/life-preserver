import CloudKit
import CryptoKit
import Foundation
import UserNotifications
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
    public static let deviceLabelKey = "sessionRenewalDeviceLabel"
    public static var defaultDeviceLabel: String {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        "Mac"
        #endif
    }
    private let cloud = PrivateUsageCloud()
    private var database: CKDatabase { CKContainer(identifier: PrivateUsageCloud.containerIdentifier).privateCloudDatabase }
    private let directoryID = CKRecord.ID(recordName: "provider-directory-v1")
    private var deviceID: String {
        if let value = UserDefaults.standard.string(forKey: "sessionRenewalDeviceID") { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: "sessionRenewalDeviceID"); return value
    }
    private var deviceLabel: String {
        let label = SessionRenewalOrigin.cleanLabel(UserDefaults.standard.string(forKey: Self.deviceLabelKey) ?? "")
        return label.isEmpty ? Self.defaultDeviceLabel : label
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
        let previousRevision = record["revision"] as? String
        let keyID = UUID().uuidString
        let key = try SharedSessionKeychain.key(owner: owner, id: keyID, create: true)
        record["provider"] = account.provider.rawValue; record["keyID"] = keyID
        record["revision"] = UUID().uuidString
        clearLease(record)
        record["payload"] = try SessionEncryption.seal(credential, key: key, context: context(record))
        do {
            try await save(record)
            if let previousRevision { SessionRenewalAlerts.clear(account: account.id, revision: previousRevision) }
        }
        catch let error as CKError where error.code == .serverRecordChanged && !replacing {
            // Another device seeded the same account first. Never overwrite its rotated session.
            guard try await contains(account.id) else { throw error }
        }
    }
    private func clearLease(_ record: CKRecord) {
        record["leaseOwner"] = nil; record["leaseUntil"] = nil; record["leaseOrigin"] = nil
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
    private func discard(_ pending: PendingRenewal, account: UUID, journal: String) throws {
        SessionRenewalAlerts.clear(account: account, revision: pending.revision)
        // A concurrent reconnect and renewal may have already written a newer journal.
        guard let data = try SharedSessionKeychain.read(journal, sync: false),
              try JSONDecoder().decode(PendingRenewal.self, from: data).revision == pending.revision else { return }
        try SharedSessionKeychain.remove(journal, sync: false)
    }
    /// A failed save must never discard a successfully rotated refresh token.
    /// A local Keychain journal lets this device complete the same transaction later.
    private func complete(_ pending: PendingRenewal, record: CKRecord, account: UUID, owner: String, journal: String) async throws -> SubscriptionCredential {
        var current = record
        for _ in 0..<4 {
            guard current["revision"] as? String == pending.revision,
                  current["leaseOwner"] as? String == deviceID,
                  let keyID = current["keyID"] as? String else {
                try discard(pending, account: account, journal: journal)
                throw SessionSharingError.changed
            }
            let key = try SharedSessionKeychain.key(owner: owner, id: keyID)
            current["revision"] = UUID().uuidString
            current["payload"] = try SessionEncryption.seal(pending.credential, key: key, context: context(current))
            clearLease(current)
            do {
                try await save(current)
            } catch let error as CKError where error.code == .serverRecordChanged {
                let latest: CKRecord?
                do { latest = try await fetch(record.recordID) }
                catch { throw SessionSharingError.pendingSync }
                guard let next = latest else {
                    try discard(pending, account: account, journal: journal)
                    throw SessionSharingError.unavailable
                }
                current = next
                continue
            } catch {
                throw SessionSharingError.pendingSync
            }
            try discard(pending, account: account, journal: journal)
            return pending.credential
        }
        throw SessionSharingError.pendingSync
    }
    public func credential(for account: SharedProviderAccount, rejectedToken: String? = nil,
                           renew: @escaping (SubscriptionCredential) async throws -> SubscriptionCredential) async throws -> SubscriptionCredential {
        let owner = try await ownerID()
        let journal = "pending|\(owner)|\(account.id.uuidString)"
        for attempt in 0..<20 {
            try Task.checkCancellation()
            let fetched = try await fetch(id(account.id))
            if let data = try SharedSessionKeychain.read(journal, sync: false) {
                let pending = try JSONDecoder().decode(PendingRenewal.self, from: data)
                if let record = fetched, record["leaseOwner"] as? String == deviceID, record["revision"] as? String == pending.revision {
                    return try await complete(pending, record: record, account: account.id, owner: owner, journal: journal)
                }
                try discard(pending, account: account.id, journal: journal)
            }
            guard var record = fetched else { throw SessionSharingError.unavailable }
            let credential = try decrypt(record, account: account, owner: owner)
            let leaseOwner = record["leaseOwner"] as? String
            let revision = record["revision"] as? String
            let decision = SessionRenewalDecision.evaluate(credential: credential, rejectedToken: rejectedToken,
                leaseOwner: leaseOwner, leaseUntil: record["leaseUntil"] as? Date, at: Date())
            switch decision {
            case .useCurrent: return credential
            case .wait:
                guard attempt < 19 else { throw SessionSharingError.renewing }
                try await Task.sleep(for: .seconds(1)); continue
            case .recover:
                let origin = (record["leaseOrigin"] as? Data).flatMap { try? JSONDecoder().decode(SessionRenewalOrigin.self, from: $0) }
                throw SessionSharingError.interrupted(device: origin?.recoveryLabel(leaseOwner: leaseOwner, revision: revision, localOwner: deviceID))
            case .acquireLease: break
            }
            guard let revision else { throw SessionSharingError.invalidSession }
            let origin = SessionRenewalOrigin(owner: deviceID, revision: revision, label: deviceLabel)
            record["leaseOwner"] = origin.owner; record["leaseUntil"] = Date().addingTimeInterval(90)
            record["leaseOrigin"] = try JSONEncoder().encode(origin)
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
                let pending = PendingRenewal(revision: revision, credential: fresh)
                try SharedSessionKeychain.write(JSONEncoder().encode(pending), account: journal, sync: false)
                await SessionRenewalAlerts.schedule(account: account, revision: revision, deviceLabel: origin.label)
                return try await self.complete(pending, record: leasedRecord, account: account.id, owner: owner, journal: journal)
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

public enum SessionRenewalAlerts {
    public static let preferenceKey = "sessionRenewalAlertsEnabled"
    public static let identifierPrefix = "sign-in-renewal-"

    public static func updatePreference(_ enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        if enabled {
            if (try? await center.requestAuthorization(options: [.alert])) != true {
                UserDefaults.standard.set(false, forKey: preferenceKey)
            }
            return
        }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        guard !UserDefaults.standard.bool(forKey: preferenceKey) else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(identifierPrefix) })
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.hasPrefix(identifierPrefix) })
    }

    static func schedule(account: SharedProviderAccount, revision: String, deviceLabel: String) async {
        guard UserDefaults.standard.bool(forKey: preferenceKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Finish syncing your \(account.provider.name) sign-in"
        content.body = "Open Life Preserver on \(deviceLabel) to finish syncing your renewed sign-in."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(account.id, revision), content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
        if !UserDefaults.standard.bool(forKey: preferenceKey) { clear(account: account.id, revision: revision) }
    }

    static func clear(account: UUID, revision: String) {
        let ids = [identifier(account, revision)]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func identifier(_ account: UUID, _ revision: String) -> String {
        "\(identifierPrefix)\(account.uuidString)-\(revision)"
    }
}
