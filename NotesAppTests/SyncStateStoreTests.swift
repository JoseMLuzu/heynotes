import CloudKit
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct SyncStateStoreTests {
    @Test func registrationAndMetadataSurviveReopenButLeasesDoNot() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let first = try SyncStateStore(directory: f.root)
        let id = try await first.registerLibrary(), scope = try f.scope()
        let lease = try await first.bind(scope, libraryID: id)
        let record = f.record()
        let stored = try await first.storeRecord(record, expectedVersion: nil, lease: lease)
        #expect(try await first.engineState(lease: lease) == nil)
        #expect(stored.systemFields.count < 1_048_576)
        try await first.close()
        let reopened = try SyncStateStore(directory: f.root)
        #expect(try await reopened.registerLibrary() == id)
        await #expect(throws: SyncStateError.inactiveLease) { try await reopened.record(record.recordID.recordName, lease: lease) }
        let next = try await reopened.bind(scope, libraryID: id)
        let restored = try #require(try await reopened.record(record.recordID.recordName, lease: next))
        #expect(restored.version == stored.version && restored.systemFields == stored.systemFields)
        let metadata = try SyncRecordSystemFields.decode(restored.systemFields, expecting: record.recordID, type: record.recordType)
        #expect(metadata.allKeys().isEmpty)
        try await reopened.close()
    }

    @Test func scopesAndLibrariesStayIsolatedAndPausingRetainsOwnership() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let store = try SyncStateStore(directory: f.root), original = try f.scope()
        let id = try await store.registerLibrary(), lease = try await store.bind(original, libraryID: id)
        let record = f.record(); _ = try await store.storeRecord(record, expectedVersion: nil, lease: lease)
        let others = [try f.scope(account: "another-user"), try f.scope(container: "iCloud.other"),
                      try f.scope(environment: .production), try f.scope(zone: "OtherZone")]
        #expect(Set(([original] + others).map(\.key)).count == 5)
        try await store.pause(libraryID: id)
        await #expect(throws: SyncStateError.inactiveLease) { try await store.record(record.recordID.recordName, lease: lease) }
        for scope in others {
            await #expect(throws: SyncStateError.differentAccount) { try await store.bind(scope, libraryID: id) }
        }
        let resumed = try await store.bind(original, libraryID: id)
        #expect(try await store.record(record.recordID.recordName, lease: resumed) != nil)
        let otherID = try await store.registerLibrary(named: "separate-local-library")
        let separate = try await store.bind(original, libraryID: otherID)
        #expect(try await store.record(record.recordID.recordName, lease: separate) == nil)
        #expect(throws: SyncStateError.invalidScope) { try f.scope(account: CKCurrentUserDefaultName) }
        try await store.close()
    }

    @Test func receiptRecoveryIsDurableAndDoesNotClearANewerPendingEdit() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let container = try PersistenceController.makeContainer(storeURL: f.userStore)
        let context = container.mainContext, book = Notebook(title: "Before send")
        context.insert(book); try context.saveRecordingSyncChanges()
        let change = try #require(context.fetch(FetchDescriptor<SyncChange>()).first)
        let sent = SyncSentRevision(identity: .init(kind: .notebook, id: book.id), revision: change.revision, operation: .upsert, packageID: UUID())
        let state = try SyncStateStore(directory: f.root), id = try await state.registerLibrary()
        let scope = try f.scope(), lease = try await state.bind(scope, libraryID: id)
        let response = f.record(sent: sent)
        _ = try await state.storeRecord(response, expectedVersion: nil, sent: sent, lease: lease)
        #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 1)
        await #expect(throws: SyncStateError.recoveryPending) { try await state.engineState(lease: lease) }
        try await state.close() // Simulated process boundary after sidecar commit, before journal save.
        book.title = "Newer local edit"; try context.saveRecordingSyncChanges()
        let newer = try #require(context.fetch(FetchDescriptor<SyncChange>()).first).revision
        #expect(newer != sent.revision)
        let reopened = try SyncStateStore(directory: f.root), next = try await reopened.bind(scope, libraryID: id)
        let ack = SyncAcknowledgementStore(modelContainer: container, libraryID: id)
        #expect(try await reopened.replayReceipts(using: ack, lease: next) == 1)
        #expect(try await reopened.pendingReceipts(lease: next).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<SyncChange>()).first?.revision == newer)
        #expect(try await reopened.engineState(lease: next) == nil)
        #expect(try await reopened.replayReceipts(using: ack, lease: next) == 0)
        // Replay after journal commit but before receipt removal is also a no-op.
        let nextSent = SyncSentRevision(identity: sent.identity, revision: newer, operation: .upsert, packageID: UUID())
        let prior = try #require(try await reopened.record(sent.identity.recordName, lease: next))
        _ = try await reopened.storeRecord(f.record(sent: nextSent), expectedVersion: prior.version, sent: nextSent, lease: next)
        try await ack.apply(reopened.pendingReceipts(lease: next))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SyncChange>()) == 0)
        try await reopened.close()
        let final = try SyncStateStore(directory: f.root), finalLease = try await final.bind(scope, libraryID: id)
        #expect(try await final.replayReceipts(using: ack, lease: finalLease) == 1)
        #expect(try await final.pendingReceipts(lease: finalLease).isEmpty)
        try await final.close()
        withExtendedLifetime(container) {}
    }

    @Test func failedSavesRetainReceiptsAndNeverRollbackTheEditorsContext() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let container = try PersistenceController.makeContainer(storeURL: f.userStore), c = container.mainContext
        let book = Notebook(title: "Saved"); c.insert(book); try c.saveRecordingSyncChanges()
        let revision = try #require(c.fetch(FetchDescriptor<SyncChange>()).first).revision
        let fail = StateSaveFailure()
        let store = try SyncStateStore(directory: f.root, save: { try fail.save($0) })
        let id = try await store.registerLibrary(), lease = try await store.bind(f.scope(), libraryID: id)
        let sent = SyncSentRevision(identity: .init(kind: .notebook, id: book.id), revision: revision, operation: .upsert, packageID: UUID())
        fail.arm()
        await #expect(throws: StateSaveFailure.Failure.self) {
            try await store.storeRecord(f.record(sent: sent), expectedVersion: nil, sent: sent, lease: lease)
        }
        #expect(try await store.record(sent.identity.recordName, lease: lease) == nil)
        #expect(try await store.pendingReceipts(lease: lease).isEmpty)
        _ = try await store.storeRecord(f.record(sent: sent), expectedVersion: nil, sent: sent, lease: lease)
        book.title = "Unsaved editor text"
        let failingAck = SyncAcknowledgementStore(modelContainer: container, libraryID: id, save: { _ in throw StateSaveFailure.Failure() })
        await #expect(throws: StateSaveFailure.Failure.self) { try await store.replayReceipts(using: failingAck, lease: lease) }
        #expect(book.title == "Unsaved editor text" && c.hasChanges)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SyncChange>()) == 1)
        #expect(try await store.pendingReceipts(lease: lease).count == 1)
        let ack = SyncAcknowledgementStore(modelContainer: container, libraryID: id)
        #expect(try await store.replayReceipts(using: ack, lease: lease) == 1)
        #expect(book.title == "Unsaved editor text" && c.hasChanges)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SyncChange>()) == 0)
        try c.saveRecordingSyncChanges()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SyncChange>()) == 1)
        try await store.close()
        withExtendedLifetime(container) {}
    }

    @Test func staleOrMismatchedCallbacksNeverOverwriteMetadataOrCreateReceipts() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let store = try SyncStateStore(directory: f.root), id = try await store.registerLibrary()
        let lease = try await store.bind(f.scope(), libraryID: id)
        let sent = SyncSentRevision(identity: .init(kind: .notebook, id: UUID()), revision: UUID(), operation: .upsert, packageID: UUID())
        let record = f.record(sent: sent), confirmation = UUID()
        let first = try await store.storeRecord(record, expectedVersion: nil, sent: sent, confirmationID: confirmation, lease: lease)
        let retry = try await store.storeRecord(record, expectedVersion: nil, sent: sent, confirmationID: confirmation, lease: lease)
        let receipts = try await store.pendingReceipts(lease: lease)
        #expect(retry.version == first.version && receipts.count == 1)
        await #expect(throws: SyncStateError.staleRecord) { try await store.storeRecord(record, expectedVersion: nil, lease: lease) }
        record["hnRevision"] = UUID().uuidString.lowercased() as NSString
        await #expect(throws: SyncStateError.invalidConfirmation) {
            try await store.storeRecord(record, expectedVersion: first.version, sent: sent, lease: lease)
        }
        let next = try await store.bind(f.scope(), libraryID: id)
        await #expect(throws: SyncStateError.inactiveLease) { try await store.storeRecord(record, expectedVersion: first.version, lease: lease) }
        #expect(try await store.record(sent.identity.recordName, lease: next)?.version == first.version)
        try await store.close()
    }

    @Test func journalAcknowledgementAndConcurrentEditorSaveShareAnAtomicBoundary() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let container = try PersistenceController.makeContainer(storeURL: f.userStore), c = container.mainContext
        let book = Notebook(title: "Sent"); c.insert(book); try c.saveRecordingSyncChanges()
        let old = try #require(c.fetch(FetchDescriptor<SyncChange>()).first).revision
        let state = try SyncStateStore(directory: f.root), id = try await state.registerLibrary()
        let lease = try await state.bind(f.scope(), libraryID: id)
        let sent = SyncSentRevision(identity: .init(kind: .notebook, id: book.id), revision: old, operation: .upsert, packageID: UUID())
        _ = try await state.storeRecord(f.record(sent: sent), expectedVersion: nil, sent: sent, lease: lease)
        let probe = AcknowledgementProbe()
        let ack = await Task.detached {
            SyncAcknowledgementStore(modelContainer: container, libraryID: id, save: { context in
                probe.record("ack-enter")
                probe.entered.signal()
                guard probe.release.wait(timeout: .now() + 5) == .success else { throw StateSaveFailure.Failure() }
                try context.save()
                probe.record("ack-exit")
            })
        }.value
        let writer = await Task.detached { StateTestWriter(modelContainer: container) }.value
        let bookID = book.id
        let editing = Task.detached {
            guard probe.waitForEntry() else { throw StateSaveFailure.Failure() }
            try await writer.edit(bookID, probe: probe)
        }
        let recovery = Task { try await state.replayReceipts(using: ack, lease: lease) }
        try await editing.value
        #expect(try await recovery.value == 1)
        #expect(probe.events == ["ack-enter", "writer-before", "ack-exit", "writer-after"])
        let pending = try #require(ModelContext(container).fetch(FetchDescriptor<SyncChange>()).first)
        #expect(pending.revision != old && pending.entityID == book.id)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Notebook>()).first?.title == "Saved during acknowledgement")
        try await state.close()
        withExtendedLifetime(container) {}
    }

    @Test func damagedCheckpointsAreRetainedAndNeverBecomeAnEmptyEngineState() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let state = try SyncStateStore(directory: f.root), id = try await state.registerLibrary()
        let scope = try f.scope(), initial = try await state.bind(scope, libraryID: id)
        let record = f.record(); _ = try await state.storeRecord(record, expectedVersion: nil, lease: initial)
        try await state.close()
        // Corrupt our storage envelope, without inventing Apple's opaque engine format.
        do {
            let schema = Schema(versionedSchema: SyncStateSchemaV2.self)
            let c = try ModelContainer(for: schema, configurations: [.init(schema: schema, url: f.root.appendingPathComponent("State.sqlite"), cloudKitDatabase: .none)])
            let library = try #require(c.mainContext.fetch(FetchDescriptor<SyncStateSchemaV2.Library>()).first)
            library.engineData = Data([0xFF, 0xFE])
            let metadata = try #require(c.mainContext.fetch(FetchDescriptor<SyncStateSchemaV1.Record>()).first)
            metadata.scopeKey = "damaged-scope-key"
            try c.mainContext.save()
        }
        let reopened = try SyncStateStore(directory: f.root), lease = try await reopened.bind(scope, libraryID: id)
        await #expect(throws: SyncStateError.damagedState) { try await reopened.engineState(lease: lease) }
        await #expect(throws: SyncStateError.damagedState) { try await reopened.record(record.recordID.recordName, lease: lease) }
        #expect(try await reopened.registerLibrary() == id)
        try await reopened.close()
        let schema = Schema(versionedSchema: SyncStateSchemaV2.self)
        let check = try ModelContainer(for: schema, configurations: [.init(schema: schema, url: f.root.appendingPathComponent("State.sqlite"), cloudKitDatabase: .none)])
        #expect(try check.mainContext.fetch(FetchDescriptor<SyncStateSchemaV2.Library>()).first?.engineData == Data([0xFF, 0xFE]))
    }

    @Test func exclusiveWriterAndUnsafeLocationsFailWithoutRemovingState() async throws {
        let f = StateFixture(); defer { f.cleanup() }
        let first = try SyncStateStore(directory: f.root), id = try await first.registerLibrary()
        #expect(throws: SyncStateError.alreadyOpen) { try SyncStateStore(directory: f.root) }
        try await first.close()
        let next = try SyncStateStore(directory: f.root)
        #expect(try await next.registerLibrary() == id)
        try await next.close()
        let linked = f.base.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: f.root)
        #expect(throws: SyncStateError.unsafePath) { try SyncStateStore(directory: linked) }
    }
}

private final class StateSaveFailure: @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var shouldFail = false
    func arm() { lock.withLock { shouldFail = true } }
    func save(_ context: ModelContext) throws {
        let fail = lock.withLock { let result = shouldFail; shouldFail = false; return result }
        if fail { throw Failure() }
        try context.save()
    }
}
private final class AcknowledgementProbe: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var values: [String] = []
    var events: [String] { lock.withLock { values } }
    func record(_ value: String) { lock.withLock { values.append(value) } }
    func waitForEntry() -> Bool { entered.wait(timeout: .now() + 5) == .success }
}

@ModelActor private actor StateTestWriter {
    func edit(_ id: UUID, probe: AcknowledgementProbe) throws {
        let context = ModelContext(modelContainer); context.autosaveEnabled = false
        let book = try #require(context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })).first)
        book.title = "Saved during acknowledgement"
        probe.record("writer-before")
        // Release from a dispatch worker, independent of MainActor and other parallel tests.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { probe.release.signal() }
        try context.saveRecordingSyncChanges()
        probe.record("writer-after")
    }
}

@MainActor private struct StateFixture {
    let base = URL.temporaryDirectory.appendingPathComponent("SyncState-\(UUID())").resolvingSymlinksInPath()
    var root: URL { base.appendingPathComponent("Sidecar") }
    var userStore: URL { base.appendingPathComponent("Notes.sqlite") }
    init() { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
    func cleanup() { try? FileManager.default.removeItem(at: base) }
    func scope(account: String = "verified-test-user", container: String = "iCloud.heynotes.tests",
               environment: SyncAccountScope.Environment = .development, zone: String = "Notes") throws -> SyncAccountScope {
        try .init(containerIdentifier: container, environment: environment, accountRecordName: account, zone: .init(zoneName: zone))
    }
    func record(sent: SyncSentRevision? = nil) -> CKRecord {
        let identity = sent?.identity ?? .init(kind: .notebook, id: UUID())
        let record = CKRecord(recordType: SyncCloudRecordPlan.entityType, recordID: .init(recordName: identity.recordName, zoneID: .init(zoneName: "Notes")))
        record["hnKind"] = identity.kind.rawValue as NSString
        record["hnRevision"] = (sent?.revision ?? UUID()).uuidString.lowercased() as NSString
        record["hnDeleted"] = (sent?.operation == .delete ? 1 : 0) as NSNumber
        return record // Synthetic response value for storage tests; no server is contacted.
    }
}
