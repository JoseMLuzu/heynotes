import SwiftData
import CryptoKit
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
                var live = Set<SyncEntityIdentity>(), counts: [String: Int] = [:]
                var enqueued = 0, preserved = 0
                func collect<T: PersistentModel>(_ type: T.Type, kind: SyncEntityKind, id: KeyPath<T, UUID> & Sendable) throws {
                    var request = FetchDescriptor<T>(sortBy: [SortDescriptor(id)])
                    request.propertiesToFetch = [id]; request.fetchLimit = 256; request.fetchOffset = 0
                    var count = 0
                    while true {
                        try Task.checkCancellation()
                        let ids = try autoreleasepool { try context.fetch(request).map { $0[keyPath: id] } }
                        guard live.count + ids.count <= Self.maximumIdentities else { throw SyncEnrollmentError.tooLarge }
                        for id in ids {
                            let identity = SyncEntityIdentity(kind: kind, id: id)
                            guard live.insert(identity).inserted, existing[identity] != .delete else { throw SyncEnrollmentError.inconsistentJournal }
                            if existing[identity] == .upsert { preserved += 1 }
                            else { context.insert(SyncChange(identity: identity, operation: .upsert)); enqueued += 1 }
                        }
                        count += ids.count; request.fetchOffset = count
                        if ids.count < 256 { break }
                    }
                    counts[kind.rawValue] = count
                }
                try collect(Folder.self, kind: .folder, id: \.id)
                try collect(Notebook.self, kind: .notebook, id: \.id)
                try collect(NotePage.self, kind: .page, id: \.id)
                try collect(NotebookSection.self, kind: .section, id: \.id)
                try collect(StudyDeck.self, kind: .deck, id: \.id)
                try collect(Flashcard.self, kind: .card, id: \.id)
                try collect(ReviewRecord.self, kind: .review, id: \.id)
                guard existing.allSatisfy({ $0.value == .delete || live.contains($0.key) }) else { throw SyncEnrollmentError.inconsistentJournal }
                let deletions = existing.values.filter { $0 == .delete }.count
                guard live.count + deletions <= Self.maximumIdentities else { throw SyncEnrollmentError.tooLarge }
                var hash = SHA256()
                for name in live.map(\.recordName).sorted() { hash.update(data: Data((name + "\n").utf8)) }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                let report = SyncEnrollmentReport(enrollmentID: enrollmentID, libraryID: libraryID, completedAt: .now,
                    entityCounts: counts, enqueued: enqueued, preservedUpserts: preserved,
                    preservedDeletions: deletions, identityDigest: digest)
                try report.validate(); try Task.checkCancellation(); try save(context)
                return report
            } catch { context.rollback(); throw error }
        }
    }
}
