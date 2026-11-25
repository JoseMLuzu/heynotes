import CloudKit

/// A real read-only adapter, separated so pagination/account-race policy can be
/// tested offline. No save/delete, zone creation, subscription or engine methods.
protocol SyncCloudInspectionTransport: Sendable {
    func accountRecordName() async throws -> String
    func page(after token: Data?) async throws -> SyncRemoteInspectionPage
}

struct CloudKitInspectionTransport: SyncCloudInspectionTransport {
    private let container: CKContainer
    private let zone: CKRecordZone.ID
    init(configuration: SyncCloudInspectionConfiguration) throws {
        try configuration.validate()
        // The future opt-in coordinator must first verify provisioning/capabilities.
        // This initializer is never called automatically or with a placeholder ID.
        container = CKContainer(identifier: configuration.containerIdentifier)
        zone = configuration.zoneID
    }
    func accountRecordName() async throws -> String {
        guard try await container.accountStatus() == .available else { throw SyncActivationError.accountUnavailable }
        return try await container.userRecordID().recordName
    }
    func page(after token: Data?) async throws -> SyncRemoteInspectionPage {
        let cursor: CKServerChangeToken?
        if let token {
            guard token.count <= 1_048_576,
                  let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: token) else {
                throw SyncActivationError.incompleteBaseline
            }
            cursor = decoded
        } else { cursor = nil }
        let result = try await container.privateCloudDatabase.recordZoneChanges(inZoneWith: zone, since: cursor,
            desiredKeys: ["hnSchema", "hnKind", "hnRevision", "hnDeleted", "hnPayloadHash", "hnHash"], resultsLimit: 200)
        var headers: [SyncRemoteHeader] = []
        for (id, value) in result.modificationResultsByID {
            let record = try value.get().record // Any per-record failure invalidates the whole review.
            guard id == record.recordID else { throw SyncActivationError.incompleteBaseline }
            headers.append(try SyncRemoteHeader(record: record, zone: zone))
        }
        let deletions = try result.deletions.map { deletion in
            guard deletion.recordID.zoneID == zone else { throw SyncActivationError.scopeMismatch }
            return SyncRemoteDeletion(name: deletion.recordID.recordName, recordType: deletion.recordType)
        }
        let bytes = try NSKeyedArchiver.archivedData(withRootObject: result.changeToken, requiringSecureCoding: true)
        return SyncRemoteInspectionPage(modifications: headers, deletions: deletions, token: bytes, moreComing: result.moreComing)
    }
}
