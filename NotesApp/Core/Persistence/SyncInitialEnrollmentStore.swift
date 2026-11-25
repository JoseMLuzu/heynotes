import SwiftData
import Foundation

/// Explicit activation work, never a launch-time scan. Only missing journal intents
/// are inserted; existing revisions/tombstones and all user metadata remain unchanged.
actor SyncInitialEnrollmentStore: ModelActor {
    static let maximumIdentities = 200_000
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let libraryID: UUID
    private let save: @Sendable (ModelContext) throws -> Void

    init(modelContainer: ModelContainer, libraryID: UUID,
         save: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }) {
        self.modelContainer = modelContainer; self.libraryID = libraryID; self.save = save
        let context = ModelContext(modelContainer); context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    func seed(enrollmentID: UUID) throws -> SyncEnrollmentReport {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer); context.autosaveEnabled = false
        return try SyncChangeJournal.withSaveBoundary {
            do {
                var query = FetchDescriptor<SyncChange>()
                query.fetchLimit = Self.maximumIdentities + 1
                let rows = try context.fetch(query)
                guard rows.count <= Self.maximumIdentities else { throw SyncEnrollmentError.tooLarge }
                var existing: [SyncEntityIdentity: SyncChangeOperation] = [:]
                for row in rows {
                    guard let kind = SyncEntityKind(rawValue: row.kindRawValue),
                          let operation = SyncChangeOperation(rawValue: row.operationRawValue) else { throw SyncEnrollmentError.inconsistentJournal }
                    let identity = SyncEntityIdentity(kind: kind, id: row.entityID)
                    guard identity.recordName == row.recordName, existing.updateValue(operation, forKey: identity) == nil else {
                        throw SyncEnrollmentError.inconsistentJournal
                    }
                }
                let inventory = try SyncIdentityInventory.capture(in: context)
                let live = inventory.identities
                var enqueued = 0, preserved = 0
                for (offset, identity) in live.enumerated() {
                    if offset.isMultiple(of: 256) { try Task.checkCancellation() }
                    guard existing[identity] != .delete else { throw SyncEnrollmentError.inconsistentJournal }
                    if existing[identity] == .upsert { preserved += 1 }
                    else { context.insert(SyncChange(identity: identity, operation: .upsert)); enqueued += 1 }
                }
                guard existing.allSatisfy({ $0.value == .delete || live.contains($0.key) }) else { throw SyncEnrollmentError.inconsistentJournal }
                let deletions = existing.values.filter { $0 == .delete }.count
                guard live.count + deletions <= Self.maximumIdentities else { throw SyncEnrollmentError.tooLarge }
                let report = SyncEnrollmentReport(enrollmentID: enrollmentID, libraryID: libraryID, completedAt: .now,
                    entityCounts: inventory.counts, enqueued: enqueued, preservedUpserts: preserved,
                    preservedDeletions: deletions, identityDigest: inventory.digest)
                try report.validate(); try Task.checkCancellation(); try save(context)
                return report
            } catch { context.rollback(); throw error }
        }
    }

}
