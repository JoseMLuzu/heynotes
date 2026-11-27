import CloudKit
import CryptoKit

/// Normalized fetched metadata. No remote name is ever used as a filesystem path.
struct SyncIncomingRecord: Codable, Equatable, Sendable {
    let name: String
    let type: String
    let changeTag: String
    let revision: UUID?
    let tombstone: Bool
    let sha256: String?
    let byteCount: UInt64?
    let blobs: [String]
    var filename: String? { sha256.map { "data-" + $0 } }

    func validate() throws {
        guard !changeTag.isEmpty, changeTag.utf8.count <= 1024 else { throw SyncIncomingError.invalidRecord }
        switch type {
        case SyncCloudRecordPlan.entityType:
            _ = try SyncRemoteHeader.identity(name)
            guard revision != nil, blobs.count <= 256, Set(blobs).count == blobs.count,
                  blobs.allSatisfy({ $0.hasPrefix("blob.") && SyncRemoteHeader.validHash(String($0.dropFirst(5))) }) else { throw SyncIncomingError.invalidRecord }
            if tombstone {
                guard sha256 == nil, byteCount == nil, blobs.isEmpty else { throw SyncIncomingError.invalidRecord }
            } else { try validateFile() }
        case SyncCloudRecordPlan.blobType:
            guard !tombstone, revision == nil, blobs.isEmpty, let sha256, name == "blob." + sha256 else { throw SyncIncomingError.invalidRecord }
            try validateFile()
        default: throw SyncIncomingError.invalidRecord
        }
    }
    private func validateFile() throws {
        guard let sha256, SyncRemoteHeader.validHash(sha256), let byteCount,
              byteCount <= SyncCloudRecordPlan.maximumAssetBytes else { throw SyncIncomingError.invalidRecord }
    }
}

struct SyncIncomingDeletion: Codable, Equatable, Sendable {
    let name: String
    let type: String
    func validate() throws {
        switch type {
        case SyncCloudRecordPlan.entityType: _ = try SyncRemoteHeader.identity(name)
        case SyncCloudRecordPlan.blobType:
            guard name.hasPrefix("blob."), SyncRemoteHeader.validHash(String(name.dropFirst(5))) else { throw SyncIncomingError.invalidRecord }
        default: throw SyncIncomingError.invalidRecord
        }
    }
}

/// Pins temporary CKAsset bytes before the delegate returns. This value performs no networking.
struct SyncIncomingInput: Sendable {
    let record: SyncIncomingRecord
    let source: SyncSourceFile?
    init(record: SyncIncomingRecord, sourceURL: URL?) throws {
        try record.validate()
        self.record = record
        if let sourceURL {
            let file = try SyncSourceFile(url: sourceURL)
            guard file.byteCount == record.byteCount else { throw SyncIncomingError.integrity }
            source = file
        } else {
            guard record.filename == nil else { throw SyncIncomingError.missingAsset }
            source = nil
        }
    }

    /// Actual SDK boundary rejects local proposals (which have no server change tag).
    init(fetched record: CKRecord, scope: SyncAccountScope) throws {
        try scope.validate()
        let header = try SyncRemoteHeader(record: record, zone: scope.zoneID)
        let normalized: SyncIncomingRecord
        let pinned: SyncSourceFile?
        switch header {
        case .entity(let value):
            let names: [String]
            if let field = record["hnBlobs"] {
                guard let array = field as? [String] else { throw SyncIncomingError.invalidRecord }
                names = array
            } else { names = [] }
            if value.deleted {
                guard record["hnPayload"] == nil, record["hnPayloadHash"] == nil, names.isEmpty else { throw SyncIncomingError.invalidRecord }
                normalized = .init(name: value.identity.recordName, type: record.recordType, changeTag: value.changeTag,
                    revision: value.revision, tombstone: true, sha256: nil, byteCount: nil, blobs: [])
                pinned = nil
            } else {
                guard let url = (record["hnPayload"] as? CKAsset)?.fileURL else { throw SyncIncomingError.missingAsset }
                let source = try SyncSourceFile(url: url)
                normalized = .init(name: value.identity.recordName, type: record.recordType, changeTag: value.changeTag,
                    revision: value.revision, tombstone: false, sha256: value.payloadHash, byteCount: source.byteCount, blobs: names.sorted())
                pinned = source
            }
        case .blob(let name, let tag):
            guard let bytes = record["hnBytes"] as? Int, bytes >= 0,
                  let url = (record["hnAsset"] as? CKAsset)?.fileURL else { throw SyncIncomingError.invalidRecord }
            let source = try SyncSourceFile(url: url)
            guard source.byteCount == UInt64(bytes) else { throw SyncIncomingError.integrity }
            normalized = .init(name: name, type: record.recordType, changeTag: tag, revision: nil,
                tombstone: false, sha256: String(name.dropFirst(5)), byteCount: UInt64(bytes), blobs: [])
            pinned = source
        }
        try normalized.validate(); self.record = normalized; source = pinned
    }

}

struct SyncIncomingManifest: Codable, Sendable {
    var version = 1
    let id: UUID
    let libraryID: UUID
    let scopeKey: String
    var receivedAt: Date = .now
    let records: [SyncIncomingRecord]
    let deletions: [SyncIncomingDeletion]

    func validate(libraryID: UUID, scope: SyncAccountScope) throws {
        guard version == 1, self.libraryID == libraryID, scopeKey == scope.key else { throw SyncIncomingError.scopeMismatch }
        guard receivedAt.timeIntervalSince1970.isFinite, !records.isEmpty || !deletions.isEmpty,
              records.count + deletions.count <= 200,
              Set(records.map(\.name)).count == records.count, Set(deletions.map(\.name)).count == deletions.count,
              Set(records.map(\.name)).isDisjoint(with: deletions.map(\.name)) else { throw SyncIncomingError.invalidRecord }
        var files: [String: UInt64] = [:]
        for record in records {
            try record.validate()
            if let file = record.filename, let size = record.byteCount {
                if let prior = files[file], prior != size { throw SyncIncomingError.integrity }
                files[file] = size
            }
        }
        for deletion in deletions { try deletion.validate() }
        guard files.values.reduce(UInt64(0), +) <= 200_000_000 else { throw SyncIncomingError.tooLarge }
    }
    var fingerprint: String {
        get throws {
            var canonical = self; canonical.receivedAt = Date(timeIntervalSince1970: 0)
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return SyncIncomingFiles.digest(try encoder.encode(canonical))
        }
    }
}

struct SyncIncomingReceipt: Sendable {
    let deliveryID: UUID
    let libraryID: UUID
    let scopeKey: String
    let recordCount: Int
    let deletionCount: Int
}

struct SyncReceivedEntity: Sendable {
    let record: SyncIncomingRecord
    let payload: SyncCloudPayload?
    /// Read-only inbox copies. A future importer must copy, never edit, these files.
    let assetFiles: [String: URL]
}

enum SyncIncomingError: LocalizedError, Equatable {
    case invalidRecord, integrity, missingAsset, scopeMismatch, deliveryMismatch, incomplete, unsafePath, closed, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The received record is unsupported or inconsistent. Local notes are unchanged."
        case .integrity: "Received data failed verification. Its files were retained; nothing was applied."
        case .missingAsset: "The received item is waiting for a required file. No empty replacement was created."
        case .scopeMismatch: "This inbox belongs to another library or cloud account. Its contents were retained."
        case .deliveryMismatch: "This delivery identifier already contains different changes. Both versions need review."
        case .incomplete: "The interrupted delivery is incomplete. Fetch its missing files again before retrying."
        case .unsafePath: "The incoming file location is unsafe. No local note was changed."
        case .closed: "The incoming store is closed. Reopen it before receiving changes."
        case .tooLarge: "This delivery exceeds the current reception limits. Local notes are unchanged."
        }
    }
}
