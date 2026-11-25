import CloudKit
import SwiftData

/// Passive, account-bound sidecar. Nothing creates this store or starts a network
/// engine during app launch; opt-in and actual account verification remain separate.
actor SyncStateStore: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    private let directory: SyncStateDirectory
    private let save: @Sendable (ModelContext) throws -> Void
    private let instanceID = UUID()
    private var closed = false
    private var applyingReceipts = false
    private var enrolling = false
    private typealias Library = SyncStateSchemaV2.Library
    private typealias Record = SyncStateSchemaV1.Record
    private typealias Receipt = SyncStateSchemaV1.Receipt

    init(directory url: URL = URL.applicationSupportDirectory.appendingPathComponent("HeyNotesSyncState", isDirectory: true),
         save: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }) throws {
        let directory = try SyncStateDirectory(url)
        let schema = Schema(versionedSchema: SyncStateSchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: directory.url.appendingPathComponent("State.sqlite"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: SyncStateMigrationPlan.self, configurations: [config])
        let context = ModelContext(container); context.autosaveEnabled = false
        self.directory = directory; self.save = save; modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    func registerLibrary(named name: String = "primary") throws -> UUID {
        try checkOpen()
        guard !name.isEmpty, name.utf8.count <= 128,
              name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) })
        else { throw SyncStateError.unknownLibrary }
        if let library = try modelContext.fetch(FetchDescriptor<Library>(predicate: #Predicate { $0.localName == name })).first { return library.id }
        let library = Library(localName: name); modelContext.insert(library)
        try commit(); return library.id
    }

    /// Only explicit enrollment/resumption can issue a lease. An existing owner is
    /// retained on pause: binding another account/scope requires a future migration policy.
    func bind(_ scope: SyncAccountScope, libraryID: UUID) throws -> SyncStateLease {
        try checkOpen(); try scope.validate()
        guard !applyingReceipts, !enrolling else { throw SyncStateError.busy }
        let library = try library(libraryID)
        guard (library.scopeData == nil) == (library.scopeKey == nil) else { throw SyncStateError.damagedState }
        if let key = library.scopeKey, key != scope.key { throw SyncStateError.differentAccount }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(scope)
        if let prior = library.scopeData, prior != bytes { throw SyncStateError.damagedState }
        library.scopeData = bytes; library.scopeKey = scope.key
        let generation = UUID(); library.activeGeneration = generation; library.engineSequence = 0
        try commit()
        return SyncStateLease(libraryID: libraryID, scope: scope, generation: generation, storeGeneration: instanceID)
    }

    func pause(libraryID: UUID) throws {
        try checkOpen()
        guard !applyingReceipts, !enrolling else { throw SyncStateError.busy }
        try library(libraryID).activeGeneration = nil
        try commit()
    }

    func record(_ name: String, lease: SyncStateLease) throws -> SyncStoredRecord? {
        _ = try validate(lease)
        guard let row = try recordRow(name, key: lease.key) else { return nil }
        _ = try SyncRecordSystemFields.decode(row.fields, expecting: .init(recordName: name, zoneID: lease.scope.zoneID), type: row.type)
        return SyncStoredRecord(recordName: row.name, recordType: row.type, systemFields: row.fields, version: row.version)
    }

    /// Invoke for trusted fetched/successfully-sent records, never for locally
    /// prepared proposals. expectedVersion is captured before the asynchronous operation.
    /// System fields and an optional sent-revision receipt commit in one sidecar transaction.
    func storeRecord(_ record: CKRecord, expectedVersion: UUID?, sent: SyncSentRevision? = nil,
                     confirmationID: UUID = UUID(), lease: SyncStateLease) throws -> SyncStoredRecord {
        try requireNoEnrollment(validate(lease))
        let name = record.recordID.recordName
        guard record.recordID.zoneID == lease.scope.zoneID,
              [SyncCloudRecordPlan.entityType, SyncCloudRecordPlan.blobType].contains(record.recordType) else {
            throw SyncStateError.invalidConfirmation
        }
        if record.recordType == SyncCloudRecordPlan.blobType {
            let hash = String(name.dropFirst(5))
            guard name.hasPrefix("blob."), hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw SyncStateError.invalidConfirmation }
        } else {
            let parts = name.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let kind = SyncEntityKind(rawValue: String(parts[0])),
                  let id = UUID(uuidString: String(parts[1])), SyncEntityIdentity(kind: kind, id: id).recordName == name else {
                throw SyncStateError.invalidConfirmation
            }
        }
        if let sent {
            guard record.recordType == SyncCloudRecordPlan.entityType, name == sent.identity.recordName,
                  record["hnKind"] as? String == sent.identity.kind.rawValue,
                  record["hnRevision"] as? String == sent.revision.uuidString.lowercased(),
                  record["hnDeleted"] as? Int == (sent.operation == .delete ? 1 : 0) else { throw SyncStateError.invalidConfirmation }
            if let receipt = try modelContext.fetch(FetchDescriptor<Receipt>(predicate: #Predicate { $0.id == confirmationID })).first {
                guard receipt.scopeKey == lease.key, receipt.entityID == sent.identity.id, receipt.kind == sent.identity.kind.rawValue,
                      receipt.revision == sent.revision, receipt.packageID == sent.packageID else { throw SyncStateError.invalidConfirmation }
                guard let existing = try self.record(name, lease: lease) else { throw SyncStateError.damagedState }
                return existing // Retrying an already committed confirmation is idempotent.
            }
        }
        let previous = try recordRow(name, key: lease.key)
        guard previous?.version == expectedVersion else { throw SyncStateError.staleRecord }
        let fields = SyncRecordSystemFields.encode(record)
        _ = try SyncRecordSystemFields.decode(fields, expecting: record.recordID, type: record.recordType)
        let row = previous ?? Record(key: lease.key + "." + name, scopeKey: lease.key, name: name, type: record.recordType, fields: fields)
        if previous == nil { modelContext.insert(row) }
        row.fields = fields; row.type = record.recordType; row.version = UUID()
        if let sent { modelContext.insert(Receipt(id: confirmationID, libraryID: lease.libraryID, scopeKey: lease.key, sent: sent)) }
        try commit()
        return SyncStoredRecord(recordName: row.name, recordType: row.type, systemFields: row.fields, version: row.version)
    }

    func pendingReceipts(lease: SyncStateLease, limit: Int = 100) throws -> [SyncSaveReceipt] {
        _ = try validate(lease)
        let key = lease.key
        var query = FetchDescriptor<Receipt>(predicate: #Predicate { $0.scopeKey == key }, sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = min(500, max(1, limit))
        return try modelContext.fetch(query).map { row in
            guard let kind = SyncEntityKind(rawValue: row.kind), row.libraryID == lease.libraryID else { throw SyncStateError.damagedState }
            return SyncSaveReceipt(id: row.id, libraryID: row.libraryID, scopeKey: row.scopeKey,
                identity: .init(kind: kind, id: row.entityID), revision: row.revision, packageID: row.packageID)
        }
    }

    /// Recovery order: sidecar receipt already committed -> journal transaction ->
    /// remove receipts. Replaying after either crash window cannot clear a newer revision.
    @discardableResult func replayReceipts(using journal: SyncAcknowledgementStore, lease: SyncStateLease) async throws -> Int {
        try requireNoEnrollment(validate(lease))
        guard !applyingReceipts else { throw SyncStateError.busy }
        guard journal.libraryID == lease.libraryID else { throw SyncStateError.unknownLibrary }
        let receipts = try pendingReceipts(lease: lease)
        guard !receipts.isEmpty else { return 0 }
        applyingReceipts = true
        defer { applyingReceipts = false }
        // Bind/pause/close are rejected during this await; they cannot revoke the
        // account lease halfway through a journal transaction in another actor.
        try await journal.apply(receipts)
        _ = try validate(lease)
        let ids = receipts.map(\.id)
        for row in try modelContext.fetch(FetchDescriptor<Receipt>(predicate: #Predicate { ids.contains($0.id) })) { modelContext.delete(row) }
        try commit()
        return receipts.count
    }

    func engineState(lease: SyncStateLease) throws -> CKSyncEngine.State.Serialization? {
        let library = try validate(lease)
        try requireNoEnrollment(library)
        guard try pendingReceipts(lease: lease, limit: 1).isEmpty else { throw SyncStateError.recoveryPending }
        guard let bytes = library.engineData else { return nil }
        guard bytes.count <= 8_388_608 else { throw SyncStateError.damagedState }
        do { return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: bytes) }
        catch { throw SyncStateError.damagedState }
    }

    /// Sequence is assigned in delegate event order before suspending. Reversed
    /// completions and callbacks from an older lease cannot overwrite a checkpoint.
    func saveEngineState(_ state: CKSyncEngine.State.Serialization, sequence: Int64, lease: SyncStateLease) throws {
        let library = try validate(lease)
        try requireNoEnrollment(library)
        guard try pendingReceipts(lease: lease, limit: 1).isEmpty else { throw SyncStateError.recoveryPending }
        guard sequence > library.engineSequence else { throw SyncStateError.staleEngineState }
        let data = try JSONEncoder().encode(state)
        guard data.count <= 8_388_608 else { throw SyncStateError.tooLarge }
        library.engineData = data; library.engineSequence = sequence
        try commit()
    }

    func close() throws {
        guard !applyingReceipts, !enrolling else { throw SyncStateError.busy }
        closed = true; directory.release()
    }

    private func library(_ id: UUID) throws -> Library {
        guard let row = try modelContext.fetch(FetchDescriptor<Library>(predicate: #Predicate { $0.id == id })).first else { throw SyncStateError.unknownLibrary }
        return row
    }

    func initialEnrollmentStatus(lease: SyncStateLease) throws -> SyncEnrollmentStatus {
        try enrollmentStatus(validate(lease))
    }

    private func enrollmentStatus(_ library: Library) throws -> SyncEnrollmentStatus {
        guard let id = library.enrollmentID else {
            guard library.enrollmentReport == nil, library.enrollmentStartedAt == nil else { throw SyncEnrollmentError.invalidInventory }
            return .notStarted
        }
        guard library.enrollmentStartedAt != nil else { throw SyncEnrollmentError.invalidInventory }
        guard let bytes = library.enrollmentReport else { return .preparing(id) }
        guard bytes.count <= 65_536, let report = try? JSONDecoder().decode(SyncEnrollmentReport.self, from: bytes),
              report.enrollmentID == id, report.libraryID == library.id else { throw SyncEnrollmentError.invalidInventory }
        try report.validate(); return .readyForRemoteReconciliation(report)
    }

    /// Durable begin -> one idempotent user-journal transaction -> durable report.
    /// A completed report prevents later activation attempts from re-enrolling records
    /// whose intents have since been acknowledged. It does not authorize cloud uploads.
    func prepareInitialEnrollment(using source: SyncInitialEnrollmentStore, lease: SyncStateLease) async throws -> SyncEnrollmentReport {
        let library = try validate(lease)
        guard !applyingReceipts, !enrolling else { throw SyncStateError.busy }
        guard source.libraryID == lease.libraryID else { throw SyncStateError.unknownLibrary }
        if case .readyForRemoteReconciliation(let report) = try initialEnrollmentStatus(lease: lease) { return report }
        guard library.engineData == nil else { throw SyncEnrollmentError.existingCheckpoint }
        guard try pendingReceipts(lease: lease, limit: 1).isEmpty else { throw SyncStateError.recoveryPending }
        if library.enrollmentID == nil {
            library.enrollmentID = UUID(); library.enrollmentStartedAt = .now
            try commit()
        }
        guard let id = library.enrollmentID else { throw SyncEnrollmentError.invalidInventory }
        enrolling = true
        defer { enrolling = false }
        let report = try await source.seed(enrollmentID: id)
        let completedLibrary = try validate(lease)
        try report.validate()
        guard report.enrollmentID == id, report.libraryID == lease.libraryID else { throw SyncEnrollmentError.invalidInventory }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        completedLibrary.enrollmentReport = try encoder.encode(report)
        try commit()
        return report
    }

    private func requireNoEnrollment(_ library: Library) throws {
        if case .preparing = try enrollmentStatus(library) { throw SyncEnrollmentError.pending }
    }
    private func recordRow(_ name: String, key scopeKey: String) throws -> Record? {
        let key = scopeKey + "." + name
        let row = try modelContext.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.key == key })).first
        if let row {
            guard row.scopeKey == scopeKey, row.name == name,
                  [SyncCloudRecordPlan.entityType, SyncCloudRecordPlan.blobType].contains(row.type) else {
                throw SyncStateError.damagedState
            }
        }
        return row
    }
    private func validate(_ lease: SyncStateLease) throws -> Library {
        try checkOpen(); try lease.scope.validate()
        guard lease.storeGeneration == instanceID else { throw SyncStateError.inactiveLease }
        let library = try library(lease.libraryID)
        guard library.scopeKey == lease.scope.key, library.activeGeneration == lease.generation else { throw SyncStateError.inactiveLease }
        guard let data = library.scopeData, let scope = try? JSONDecoder().decode(SyncAccountScope.self, from: data), scope == lease.scope else {
            throw SyncStateError.damagedState
        }
        return library
    }
    private func checkOpen() throws { guard !closed else { throw SyncStateError.closed }; try Task.checkCancellation() }
    private func commit() throws {
        do { try save(modelContext) } catch { modelContext.rollback(); throw error }
    }
}
