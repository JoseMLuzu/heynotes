import CloudKit

/// A local proposal only. Constructing these records never accesses an account/database.
/// Retain its source package until all future operations using its CKAssets have ended.
struct SyncCloudRecordPlan: Sendable {
    static let entityType = "HNEntityV1"
    static let blobType = "HNBlobV1"
    // Conservative product preflight, not a claim of CloudKit's current server limit.
    static let maximumAssetBytes: UInt64 = 40_000_000

    let packageID: UUID
    let identity: SyncEntityIdentity
    let revision: UUID
    let entity: CKRecord
    let blobs: [CKRecord]

    /// Save blobs before the entity, or in a suitable atomic batch. These are not
    /// automatically scheduled or acknowledged; stable blob IDs alone don't skip uploads.
    var recordsToSave: [CKRecord] { blobs + [entity] }

    static func validateZone(_ zone: CKRecordZone.ID) throws {
        guard zone.zoneName != CKRecordZone.ID.defaultZoneName, !zone.zoneName.isEmpty,
              zone.zoneName.utf8.count <= 255, zone.zoneName.utf8.allSatisfy({ $0 < 128 }),
              !zone.ownerName.isEmpty else { throw SyncCloudError.invalidZone }
    }

    static func make(package: PreparedSyncUpload, zone: CKRecordZone.ID, payloadURL: URL?,
                     payloadHash: String?, systemFields: [String: Data]) throws -> Self {
        try validateZone(zone)
        func record(_ type: String, name: String) throws -> CKRecord {
            let id = CKRecord.ID(recordName: name, zoneID: zone)
            if let fields = systemFields[name] {
                return try SyncRecordSystemFields.decode(fields, expecting: id, type: type)
            }
            return CKRecord(recordType: type, recordID: id)
        }
        let manifest = package.manifest
        let entity = try record(entityType, name: manifest.identity.recordName)
        entity["hnSchema"] = 1 as NSNumber
        entity["hnKind"] = manifest.identity.kind.rawValue as NSString
        entity["hnRevision"] = manifest.revision.uuidString.lowercased() as NSString
        entity["hnDeleted"] = (manifest.operation == .delete ? 1 : 0) as NSNumber
        // Explicit nil assignments mark old server fields for clearing under changedKeys.
        entity["hnPayload"] = nil
        entity["hnPayloadHash"] = nil
        entity["hnBlobs"] = nil
        var blobs: [CKRecord] = []
        if manifest.operation == .upsert {
            guard let payloadURL, let payloadHash else { throw SyncCloudError.invalidMetadata }
            entity["hnPayload"] = CKAsset(fileURL: payloadURL)
            entity["hnPayloadHash"] = payloadHash as NSString
            var seen = Set<String>()
            for asset in manifest.assets.sorted(by: { $0.sha256 < $1.sha256 }) where seen.insert(asset.sha256).inserted {
                let blob = try record(blobType, name: "blob.\(asset.sha256)")
                blob["hnSchema"] = 1 as NSNumber
                blob["hnHash"] = asset.sha256 as NSString
                blob["hnBytes"] = NSNumber(value: asset.byteCount)
                blob["hnAsset"] = CKAsset(fileURL: package.assetURL(asset))
                blobs.append(blob)
            }
            if !blobs.isEmpty { entity["hnBlobs"] = blobs.map { $0.recordID.recordName } as NSArray }
        }
        // A deletion intent becomes a durable entity tombstone, never a hard delete
        // or a cascade that could destroy another note's shared PDF/image/font.
        return Self(packageID: manifest.id, identity: manifest.identity, revision: manifest.revision,
                    entity: entity, blobs: blobs)
    }
}
