import CloudKit

/// Development setup only. No user record, asset, subscription or deletion API.
protocol SyncDevelopmentZoneTransport: Sendable {
    func accountRecordName() async throws -> String
    func zoneExists() async throws -> Bool
    func createZone() async throws
}

struct CloudKitDevelopmentZoneTransport: SyncDevelopmentZoneTransport {
    private let container: CKContainer
    private let zone: CKRecordZone.ID
    init(configuration: SyncCloudInspectionConfiguration) throws {
        #if DEBUG
        try configuration.validate()
        guard configuration.environment == .development else { throw SyncDevelopmentZoneError.developmentOnly }
        container = CKContainer(identifier: configuration.containerIdentifier)
        zone = configuration.zoneID
        #else
        throw SyncDevelopmentZoneError.developmentOnly
        #endif
    }
    func accountRecordName() async throws -> String {
        guard try await container.accountStatus() == .available else { throw SyncActivationError.accountUnavailable }
        return try await container.userRecordID().recordName
    }
    func zoneExists() async throws -> Bool {
        do {
            let value = try await container.privateCloudDatabase.recordZone(for: zone)
            guard value.zoneID == zone else { throw SyncDevelopmentZoneError.invalidResult }
            return true
        } catch let error as CKError where error.code == .zoneNotFound {
            return false // Missing setup, never a claim that remote documents are empty.
        }
    }
    func createZone() async throws {
        #if DEBUG
        let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
        guard result.deleteResults.isEmpty, result.saveResults.count == 1,
              let saved = result.saveResults[zone] else { throw SyncDevelopmentZoneError.invalidResult }
        guard try saved.get().zoneID == zone else { throw SyncDevelopmentZoneError.invalidResult }
        #else
        throw SyncDevelopmentZoneError.developmentOnly
        #endif
    }
}
