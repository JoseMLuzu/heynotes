import CloudKit
import CryptoKit

/// Explicit private-database identity. Never substitute CKCurrentUserDefaultName
/// for the real account record name obtained by a future authenticated adapter.
struct SyncAccountScope: Codable, Equatable, Sendable {
    enum Environment: String, Codable, Sendable { case development, production }
    let containerIdentifier: String
    let environment: Environment
    let accountRecordName: String
    let zoneName: String
    let zoneOwnerName: String

    init(containerIdentifier: String, environment: Environment, accountRecordName: String,
         zone: CKRecordZone.ID) throws {
        self.containerIdentifier = containerIdentifier; self.environment = environment
        self.accountRecordName = accountRecordName; zoneName = zone.zoneName; zoneOwnerName = zone.ownerName
        try validate()
    }

    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName) }
    var key: String {
        // Length-delimited fields prevent ambiguous concatenation; no raw account name in keys.
        let values = [containerIdentifier, environment.rawValue, accountRecordName, zoneName, zoneOwnerName]
        let bytes = values.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(bytes.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func validate() throws {
        guard containerIdentifier.hasPrefix("iCloud."), containerIdentifier.utf8.count <= 255,
              [containerIdentifier, accountRecordName, zoneName, zoneOwnerName].allSatisfy({
                  !$0.isEmpty && $0.utf8.count <= 512 && !$0.contains("\0") && !$0.contains("\n")
              }), accountRecordName != CKCurrentUserDefaultName,
              zoneName != CKRecordZone.ID.defaultZoneName, zoneName.utf8.count <= 255,
              zoneName.utf8.allSatisfy({ $0 < 128 }) else { throw SyncStateError.invalidScope }
    }
}

struct SyncStateLease: Sendable {
    let libraryID: UUID
    let scope: SyncAccountScope
    let generation: UUID
    let storeGeneration: UUID
    var key: String { libraryID.uuidString.lowercased() + "." + scope.key }
}

struct SyncStoredRecord: Sendable {
    let recordName: String
    let recordType: String
    let systemFields: Data
    let version: UUID
}

/// Captured sent revision, not a new local mutation. Only a successful send handler
/// may supply this to storeRecord; preparing CKRecords is not a confirmation.
struct SyncSentRevision: Sendable {
    let identity: SyncEntityIdentity
    let revision: UUID
    let operation: SyncChangeOperation
    let packageID: UUID
}

struct SyncSaveReceipt: Sendable {
    let id: UUID
    let libraryID: UUID
    let scopeKey: String
    let identity: SyncEntityIdentity
    let revision: UUID
    let packageID: UUID
}

enum SyncStateError: LocalizedError, Equatable {
    case invalidScope, unknownLibrary, differentAccount, inactiveLease, staleRecord, staleEngineState
    case damagedState, invalidConfirmation, recoveryPending, busy, alreadyOpen, closed, unsafePath, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidScope: "A verified account, container and custom private zone are required."
        case .unknownLibrary: "This local library has not been registered for synchronization."
        case .differentAccount: "This library is already linked to another cloud scope. Its notes and cloud state have been retained."
        case .inactiveLease: "This sync session is no longer active. Its late callback was ignored."
        case .staleRecord: "Newer cloud metadata is already stored. Reconcile the record before retrying."
        case .staleEngineState: "A newer engine checkpoint is already stored for this session."
        case .damagedState: "The local sync state could not be read. It has been retained for recovery."
        case .invalidConfirmation: "The confirmation does not match the sent record and revision."
        case .recoveryPending: "Finish recovering confirmed changes before restoring or saving engine state."
        case .busy: "Sync acknowledgement recovery is still in progress."
        case .alreadyOpen: "Another sync-state writer is already using this directory."
        case .closed: "This sync-state store is closed."
        case .unsafePath: "The sync-state directory contains an unsupported file location."
        case .tooLarge: "The sync checkpoint exceeds the supported local-state size."
        }
    }
}
