import CloudKit
import Foundation
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

/// Both apps use the same container and only the signed-in user's private database.
/// One Mac publishes a single replacement snapshot; the companion is read-only.
public struct PrivateUsageCloud {
    public static var containerIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "LifePreserverCloudContainerIdentifier") as? String
            ?? "iCloud.com.example.lifepreserver"
    }
    private static let recordID = CKRecord.ID(recordName: "current-usage-v1")
    public init() {}

    private var container: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    public func ownerID() async throws -> String {
        switch try await container.accountStatus() {
        case .available: break
        case .noAccount: throw SyncError.signIn
        case .restricted: throw SyncError.restricted
        case .couldNotDetermine, .temporarilyUnavailable: throw SyncError.accountUnavailable
        @unknown default: throw SyncError.accountUnavailable
        }
        return try await container.userRecordID().recordName
    }

    public func publish(_ snapshot: MobileSnapshot) async throws {
        _ = try await ownerID()
        try Task.checkCancellation()
        let record = CKRecord(recordType: "UsageSnapshot", recordID: Self.recordID)
        record["payload"] = try JSONEncoder().encode(snapshot) as NSData
        // Replacement, not merging: removed accounts and stopped sharing must clear
        // the prior payload. The Mac coordinator serializes all writes.
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        guard let saved = result.saveResults[Self.recordID] else { throw SyncError.invalidReading }
        _ = try saved.get()
    }

    public func fetch() async throws -> MobileSnapshot? {
        do {
            let record = try await container.privateCloudDatabase.record(for: Self.recordID)
            guard let data = record["payload"] as? Data else { throw SyncError.invalidReading }
            return try MobileSnapshot.decode(data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    public static func message(for error: Error) -> String {
        if let error = error as? SyncError { return error.localizedDescription }
        if error is DecodingError || error is MobileSnapshot.SnapshotError {
            return "The shared reading couldn’t be opened. Update Life Preserver on both devices."
        }
        guard let error = error as? CKError else { return "The connection check didn’t finish. Please try again." }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in Settings, then try again."
        case .networkUnavailable, .networkFailure:
            return "This device couldn’t reach iCloud. Check Wi-Fi or cellular access and retry."
        case .badContainer, .badDatabase, .missingEntitlement, .permissionFailure:
            return "This app’s iCloud connection needs setup. Update Life Preserver on both devices."
        case .serviceUnavailable, .zoneBusy, .internalError, .serverRejectedRequest, .serverResponseLost:
            return "iCloud couldn’t complete the request. Try again shortly."
        case .requestRateLimited:
            return "iCloud has paused usage checks. Please wait before trying again."
        case .accountTemporarilyUnavailable:
            return "Your iCloud account is temporarily unavailable. Try again shortly."
        case .operationCancelled:
            return "The connection check was interrupted. Please try again."
        case .quotaExceeded: return "Your iCloud storage is full. Free some space, then try again."
        case .incompatibleVersion: return "Update Life Preserver on both your Mac and mobile device."
        default: return "The iCloud connection check failed. Please try again."
        }
    }

    /// Diagnostics contain only error domains/codes and decoding field names,
    /// never payloads, account identifiers, credentials or CloudKit userInfo.
    public static func diagnosticCode(for error: Error) -> String {
        if case DecodingError.keyNotFound(let key, _) = error { return "decode:missing-\(key.stringValue)" }
        if error is DecodingError { return "decode:invalid-payload" }
        let ns = error as NSError
        var code = "\(ns.domain):\(ns.code)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            code += " / \(underlying.domain):\(underlying.code)"
        }
        return code
    }

    public static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? CKError)?.code == .operationCancelled
            || (error as? URLError)?.code == .cancelled
    }

    public enum SyncError: LocalizedError {
        case signIn, invalidReading, restricted, accountUnavailable
        public var errorDescription: String? {
            switch self {
            case .signIn: return "Sign in to iCloud in Settings, then try again."
            case .invalidReading: return "This reading couldn’t be opened. Update both apps and sync again."
            case .restricted: return "iCloud access is restricted on this device. Check your iCloud settings."
            case .accountUnavailable: return "Your iCloud account isn’t ready to sync yet. Try again shortly."
            }
        }
    }
}
