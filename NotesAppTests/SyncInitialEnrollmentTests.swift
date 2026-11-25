import CloudKit
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct SyncInitialEnrollmentTests {
    @Test func legacyLibrarySeedsAllKindsIncludingTrashAndPreservesExistingIntentTokens() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let c = f.container.mainContext
        let folder = Folder(title: "University"), book = Notebook(title: "Legacy"), section = NotebookSection(title: "Unit 1", sortIndex: 0)
        let page = NotePage(pageIndex: 2, id: book.id), deck = StudyDeck(title: "Study", notebookID: book.id)
        let card = Flashcard(question: "Q", answer: "A", sourceNotebookID: book.id, sourcePageID: page.id)
        let review = ReviewRecord(rating: "good", reviewedAt: .now, nextReviewAt: .now, intervalSeconds: 123)
        c.insert(folder); c.insert(book); c.insert(section); c.insert(page); c.insert(deck); c.insert(card); c.insert(review)
        book.folder = folder; book.pages = [page]; book.sections = [section]; page.section = section
        deck.cards = [card]; card.reviews = [review]; folder.trashedAt = .now
        page.drawingFilePath = "Original/ink.drawing"; page.objectsData = Data([9, 8, 7])
        let ink = Data([3, 1, 4]); try ink.write(to: f.base.appendingPathComponent("source-ink"))
        try c.save() // Deliberate pre-journal fixture, including unreadable content: no decoding here.
        let edited = SyncChange(identity: .init(kind: .page, id: page.id), operation: .upsert)
        let deleted = SyncChange(identity: .init(kind: .notebook, id: UUID()), operation: .delete)
        c.insert(edited); c.insert(deleted); try c.save()
        let tokens = [edited.recordName: edited.revision, deleted.recordName: deleted.revision]
        let dates = [book.updatedAt, page.updatedAt]
        let store = try SyncStateStore(directory: f.stateRoot), id = try await store.registerLibrary()
        let lease = try await store.bind(f.scope, libraryID: id)
        let source = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: id)
        let report = try await store.prepareInitialEnrollment(using: source, lease: lease)
        #expect(report.entityCount == 7 && report.enqueued == 6 && report.preservedUpserts == 1 && report.preservedDeletions == 1)
        #expect(report.entityCounts.values.allSatisfy { $0 == 1 })
        let rows = try ModelContext(f.container).fetch(FetchDescriptor<SyncChange>())
        #expect(rows.count == 8 && Set(rows.map(\.recordName)).count == 8)
        #expect(rows.filter { tokens[$0.recordName] != nil }.allSatisfy { tokens[$0.recordName] == $0.revision })
        #expect([book.updatedAt, page.updatedAt] == dates && page.pageIndex == 2)
        #expect(page.objectsData == Data([9, 8, 7]) && page.drawingFilePath == "Original/ink.drawing")
        #expect(card.sourcePageID == page.id && card.sourceNotebookID == book.id && review.intervalSeconds == 123)
        #expect(try Data(contentsOf: f.base.appendingPathComponent("source-ink")) == ink)
        let again = try await store.prepareInitialEnrollment(using: source, lease: lease)
        #expect(again.enrollmentID == report.enrollmentID && again.identityDigest == report.identityDigest)
        // A completed marker prevents reseeding a record whose intent was already confirmed.
        let observer = ModelContext(f.container)
        observer.delete(try #require(observer.fetch(FetchDescriptor<SyncChange>()).first { $0.recordName == edited.recordName }))
        try observer.save()
        _ = try await store.prepareInitialEnrollment(using: source, lease: lease)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 7)
        try await store.close()
    }

    @Test func failedFinalMarkerResumesAfterReopenWithoutReplacingSeededRevisions() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, book = Notebook(title: "Resume")
        c.insert(book); try c.save()
        let failure = EnrollmentFailure()
        let state = try SyncStateStore(directory: f.stateRoot, save: { try failure.save($0) })
        let id = try await state.registerLibrary(), lease = try await state.bind(f.scope, libraryID: id)
        failure.arm(after: 2) // Begin commits; final report save fails after the journal transaction.
        let source = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: id)
        await #expect(throws: EnrollmentFailure.Failure.self) { try await state.prepareInitialEnrollment(using: source, lease: lease) }
        guard case .preparing(let enrollmentID) = try await state.initialEnrollmentStatus(lease: lease) else { Issue.record("Missing durable begin marker"); return }
        let revision = try #require(ModelContext(f.container).fetch(FetchDescriptor<SyncChange>()).first).revision
        await #expect(throws: SyncEnrollmentError.pending) { try await state.engineState(lease: lease) }
        try await state.close()
        let reopened = try SyncStateStore(directory: f.stateRoot), resumed = try await reopened.bind(f.scope, libraryID: id)
        let report = try await reopened.prepareInitialEnrollment(using: source, lease: resumed)
        #expect(report.enrollmentID == enrollmentID && report.enqueued == 0 && report.preservedUpserts == 1)
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<SyncChange>()).first?.revision == revision)
        guard case .readyForRemoteReconciliation = try await reopened.initialEnrollmentStatus(lease: resumed) else { Issue.record("Expected local completion only"); return }
        try await reopened.close()
    }

    @Test func seedFailureAndCancellationNeverChangeUserMetadataOrPartiallyCommitRows() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, book = Notebook(title: "Saved")
        c.insert(book); try c.save()
        let state = try SyncStateStore(directory: f.stateRoot), id = try await state.registerLibrary()
        let lease = try await state.bind(f.scope, libraryID: id)
        book.title = "Unsaved editor title"
        let failing = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: id, save: { _ in throw EnrollmentFailure.Failure() })
        await #expect(throws: EnrollmentFailure.Failure.self) { try await state.prepareInitialEnrollment(using: failing, lease: lease) }
        #expect(book.title == "Unsaved editor title" && c.hasChanges)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 0)
        let source = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: id)
        let task = Task { try await source.seed(enrollmentID: UUID()) }; task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 0)
        try await state.close()
    }

    @Test func inconsistentDeletionOrOrphanUpsertAbortsWithoutSilentlyRepairingTheJournal() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, book = Notebook(title: "Keep")
        c.insert(book); c.insert(Folder(title: "Would enqueue first")); try c.save()
        let stale = SyncChange(identity: .init(kind: .notebook, id: book.id), operation: .delete)
        c.insert(stale); try c.save()
        let source = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: UUID())
        await #expect(throws: SyncEnrollmentError.inconsistentJournal) { try await source.seed(enrollmentID: UUID()) }
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 1)
        stale.operationRawValue = "upsert"; stale.entityID = UUID()
        stale.recordName = SyncEntityIdentity(kind: .notebook, id: stale.entityID).recordName; try c.save()
        await #expect(throws: SyncEnrollmentError.inconsistentJournal) { try await source.seed(enrollmentID: UUID()) }
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 1)
        #expect(book.title == "Keep")
    }

    @Test func pagedInventoryIsDeterministicAndEmptyLibrariesRemainLocalOnly() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let source = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: UUID())
        let empty = try await source.seed(enrollmentID: UUID())
        #expect(empty.entityCount == 0 && empty.enqueued == 0)
        let c = f.container.mainContext, book = Notebook(title: "Long notebook")
        c.insert(book)
        for index in 0..<270 {
            let page = NotePage(pageIndex: index); c.insert(page); book.pages.append(page)
        }
        try c.save()
        let first = try await source.seed(enrollmentID: UUID()), next = try await source.seed(enrollmentID: UUID())
        #expect(first.entityCount == 271 && first.enqueued == 271)
        #expect(next.enqueued == 0 && next.preservedUpserts == 271 && next.identityDigest == first.identityDigest)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 271)
    }

    @Test func sidecarV1MigratesToV2WithoutChangingOwnershipFieldsReceiptsOrCheckpointBytes() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let identity = SyncEntityIdentity(kind: .notebook, id: UUID()), libraryID: UUID
        let sent = SyncSentRevision(identity: identity, revision: UUID(), operation: .upsert, packageID: UUID())
        let record = CKRecord(recordType: SyncCloudRecordPlan.entityType, recordID: .init(recordName: identity.recordName, zoneID: f.scope.zoneID))
        let fields = SyncRecordSystemFields.encode(record), receiptID = UUID()
        try FileManager.default.createDirectory(at: f.stateRoot, withIntermediateDirectories: true)
        do {
            let schema = Schema(versionedSchema: SyncStateSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [.init(schema: schema, url: f.stateRoot.appendingPathComponent("State.sqlite"), cloudKitDatabase: .none)])
            let library = SyncStateSchemaV1.Library(localName: "primary"); libraryID = library.id
            library.scopeData = try encoder.encode(f.scope); library.scopeKey = f.scope.key
            library.engineData = Data([0xFE]); library.engineSequence = 19
            let key = libraryID.uuidString.lowercased() + "." + f.scope.key
            let metadata = SyncStateSchemaV1.Record(key: key + "." + identity.recordName, scopeKey: key, name: identity.recordName,
                type: record.recordType, fields: fields)
            container.mainContext.insert(library); container.mainContext.insert(metadata)
            container.mainContext.insert(SyncStateSchemaV1.Receipt(id: receiptID, libraryID: libraryID, scopeKey: key, sent: sent))
            try container.mainContext.save()
        }
        let migrated = try SyncStateStore(directory: f.stateRoot)
        #expect(try await migrated.registerLibrary() == libraryID)
        let lease = try await migrated.bind(f.scope, libraryID: libraryID)
        #expect(try await migrated.record(identity.recordName, lease: lease)?.systemFields == fields)
        #expect(try await migrated.pendingReceipts(lease: lease).first?.id == receiptID)
        guard case .notStarted = try await migrated.initialEnrollmentStatus(lease: lease) else { Issue.record("Migration must not enroll automatically"); return }
        let raw = ModelContext(migrated.modelContainer)
        #expect(try raw.fetch(FetchDescriptor<SyncStateSchemaV2.Library>()).first?.engineData == Data([0xFE]))
        try await migrated.close()
    }

    @Test func wrongLibraryAndDamagedCompletionReportsCannotSilentlyAuthorizeActivation() async throws {
        let f = try EnrollmentFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, book = Notebook(title: "Retain")
        c.insert(book); try c.save()
        let state = try SyncStateStore(directory: f.stateRoot), id = try await state.registerLibrary()
        let lease = try await state.bind(f.scope, libraryID: id)
        let wrong = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: UUID())
        await #expect(throws: SyncStateError.unknownLibrary) { try await state.prepareInitialEnrollment(using: wrong, lease: lease) }
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<SyncChange>()) == 0)
        let source = SyncInitialEnrollmentStore(modelContainer: f.container, libraryID: id)
        _ = try await state.prepareInitialEnrollment(using: source, lease: lease)
        let revision = try #require(ModelContext(f.container).fetch(FetchDescriptor<SyncChange>()).first).revision
        try await state.close()
        do {
            let schema = Schema(versionedSchema: SyncStateSchemaV2.self)
            let raw = try ModelContainer(for: schema, configurations: [.init(schema: schema,
                url: f.stateRoot.appendingPathComponent("State.sqlite"), cloudKitDatabase: .none)])
            let library = try #require(raw.mainContext.fetch(FetchDescriptor<SyncStateSchemaV2.Library>()).first)
            library.enrollmentReport = Data([0xFF]); try raw.mainContext.save()
        }
        let reopened = try SyncStateStore(directory: f.stateRoot), resumed = try await reopened.bind(f.scope, libraryID: id)
        await #expect(throws: SyncEnrollmentError.invalidInventory) { try await reopened.initialEnrollmentStatus(lease: resumed) }
        await #expect(throws: SyncEnrollmentError.invalidInventory) { try await reopened.engineState(lease: resumed) }
        await #expect(throws: SyncEnrollmentError.invalidInventory) { try await reopened.prepareInitialEnrollment(using: source, lease: resumed) }
        #expect(try ModelContext(f.container).fetch(FetchDescriptor<SyncChange>()).first?.revision == revision)
        try await reopened.close()
    }
}

private final class EnrollmentFailure: @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var countdown: Int?
    func arm(after count: Int) { lock.withLock { countdown = count } }
    func save(_ context: ModelContext) throws {
        let fail = lock.withLock {
            guard let count = countdown else { return false }
            countdown = count > 1 ? count - 1 : nil
            return count == 1
        }
        if fail { throw Failure() }
        try context.save()
    }
}

@MainActor private struct EnrollmentFixture {
    let base = URL.temporaryDirectory.appendingPathComponent("SyncEnrollment-\(UUID())").resolvingSymlinksInPath()
    let container: ModelContainer
    let scope: SyncAccountScope
    var stateRoot: URL { base.appendingPathComponent("State") }
    init() throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(storeURL: base.appendingPathComponent("Notes.sqlite"))
        scope = try .init(containerIdentifier: "iCloud.heynotes.tests", environment: .development,
            accountRecordName: "offline-enrollment-test", zone: .init(zoneName: "Notes"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: base) }
}
