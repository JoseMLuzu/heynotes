import CloudKit
import CryptoKit

struct SyncCloudInspectionConfiguration: Sendable {
    let containerIdentifier: String
    let environment: SyncAccountScope.Environment
    let zoneName: String

    func validate() throws {
        guard containerIdentifier.hasPrefix("iCloud."), containerIdentifier.utf8.count > 7,
              containerIdentifier.utf8.count <= 255, !zoneName.isEmpty, zoneName.utf8.count <= 255,
              zoneName != CKRecordZone.ID.defaultZoneName,
              containerIdentifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              containerIdentifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46].contains($0) }),
              [containerIdentifier, zoneName].allSatisfy({ $0.utf8.allSatisfy { $0 >= 32 && $0 < 127 } }) else {
            throw SyncActivationError.invalidConfiguration
        }
    }
    var zoneID: CKRecordZone.ID { .init(zoneName: zoneName, ownerName: CKCurrentUserDefaultName) }
}

struct SyncRemoteEntityHeader: Sendable {
    let identity: SyncEntityIdentity
    let revision: UUID
    let deleted: Bool
    let payloadHash: String?
    let changeTag: String
}

enum SyncRemoteHeader: Sendable {
    case entity(SyncRemoteEntityHeader)
    case blob(name: String, changeTag: String)
    var name: String {
        switch self { case .entity(let value): value.identity.recordName; case .blob(let name, _): name }
    }
    func validate() throws {
        switch self {
        case .entity(let header):
            guard !header.changeTag.isEmpty, header.deleted ? header.payloadHash == nil : header.payloadHash.map(Self.validHash) == true else {
                throw SyncActivationError.unsupportedRecord
            }
        case .blob(let name, let changeTag):
            guard !changeTag.isEmpty, name.hasPrefix("blob."), Self.validHash(String(name.dropFirst(5))) else { throw SyncActivationError.unsupportedRecord }
        }
    }
    static func identity(_ name: String) throws -> SyncEntityIdentity {
        let parts = name.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let kind = SyncEntityKind(rawValue: String(parts[0])), let id = UUID(uuidString: String(parts[1])) else {
            throw SyncActivationError.unsupportedRecord
        }
        let identity = SyncEntityIdentity(kind: kind, id: id)
        guard identity.recordName == name else { throw SyncActivationError.unsupportedRecord }
        return identity
    }
    static func validHash(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    init(record: CKRecord, zone: CKRecordZone.ID) throws {
        guard record.recordID.zoneID == zone, record["hnSchema"] as? Int == 1, let tag = record.recordChangeTag, !tag.isEmpty else {
            throw SyncActivationError.unsupportedRecord
        }
        let name = record.recordID.recordName
        switch record.recordType {
        case SyncCloudRecordPlan.entityType:
            let identity = try Self.identity(name)
            guard record["hnKind"] as? String == identity.kind.rawValue,
                  let revision = record["hnRevision"] as? String, let id = UUID(uuidString: revision),
                  id.uuidString.lowercased() == revision, let deleted = record["hnDeleted"] as? Int, [0, 1].contains(deleted) else {
                throw SyncActivationError.unsupportedRecord
            }
            self = .entity(.init(identity: identity, revision: id, deleted: deleted == 1,
                payloadHash: record["hnPayloadHash"] as? String, changeTag: tag))
        case SyncCloudRecordPlan.blobType:
            guard record["hnHash"] as? String == String(name.dropFirst(5)) else { throw SyncActivationError.unsupportedRecord }
            self = .blob(name: name, changeTag: tag)
        default: throw SyncActivationError.unsupportedRecord
        }
        try validate()
    }
}

struct SyncRemoteDeletion: Sendable { let name: String; let recordType: String }
struct SyncRemoteInspectionPage: Sendable {
    let modifications: [SyncRemoteHeader]
    let deletions: [SyncRemoteDeletion]
    let token: Data
    let moreComing: Bool
}

/// Complete header-only observation. It carries no permission to overwrite anything.
struct SyncRemoteBaseline: Sendable {
    let id: UUID
    let scope: SyncAccountScope
    let entities: [SyncEntityIdentity: SyncRemoteEntityHeader]
    let blobNames: Set<String>
    let deletedEntities: Set<SyncEntityIdentity>
    let finalToken: Data
    func validate() throws {
        try scope.validate()
        guard !finalToken.isEmpty, finalToken.count <= 1_048_576,
              entities.count + blobNames.count + deletedEntities.count <= 400_000,
              Set(entities.keys).isDisjoint(with: deletedEntities) else { throw SyncActivationError.incompleteBaseline }
        for (identity, header) in entities {
            guard identity == header.identity else { throw SyncActivationError.incompleteBaseline }
            try SyncRemoteHeader.entity(header).validate()
        }
        for name in blobNames {
            guard name.hasPrefix("blob."), SyncRemoteHeader.validHash(String(name.dropFirst(5))) else { throw SyncActivationError.unsupportedRecord }
        }
    }
    var fingerprint: String {
        let headers = entities.values.map {
            "entity:\($0.identity.recordName):\($0.revision):\($0.deleted):\($0.payloadHash ?? ""):\($0.changeTag.utf8.count):\($0.changeTag)"
        }
        let tokenHash = SHA256.hash(data: finalToken).map { String(format: "%02x", $0) }.joined()
        return SyncIdentityInventory.digest(headers + blobNames.map { "blob:" + $0 }
            + deletedEntities.map { "deleted:" + $0.recordName } + ["scope:" + scope.key, "token:" + tokenHash])
    }
}
