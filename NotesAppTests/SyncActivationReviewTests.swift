import CloudKit
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct SyncActivationReviewTests {
    private let configuration = SyncCloudInspectionConfiguration(containerIdentifier: "iCloud.heynotes.tests", environment: .development, zoneName: "Notes")
    private func header(_ identity: SyncEntityIdentity, deleted: Bool = false, tag: String = "server-tag") -> SyncRemoteEntityHeader {
        .init(identity: identity, revision: UUID(), deleted: deleted, payloadHash: deleted ? nil : String(repeating: "a", count: 64), changeTag: tag)
    }
    private func scope(account: String = "account-a") throws -> SyncAccountScope {
        try .init(containerIdentifier: configuration.containerIdentifier, environment: configuration.environment,
            accountRecordName: account, zone: configuration.zoneID)
    }
    private func page(_ headers: [SyncRemoteHeader] = [], deletions: [SyncRemoteDeletion] = [], token: String = "cursor", more: Bool = false) -> SyncRemoteInspectionPage {
        .init(modifications: headers, deletions: deletions, token: Data(token.utf8), moreComing: more)
    }

    @Test func missingOrMalformedConfigurationNeverCreatesAClient() async throws {
        let count = InspectionFactoryCount()
        let reader = FixtureInspectionTransport(pages: [page()])
        let inspector = SyncCloudActivationInspector(transport: { _ in count.increment(); return reader })
        await #expect(throws: SyncActivationError.notConfigured) { try await inspector.inspect(configuration: nil) }
        for config in [SyncCloudInspectionConfiguration(containerIdentifier: "iCloud.", environment: .development, zoneName: "Notes"),
                       .init(containerIdentifier: "iCloud.bad name", environment: .development, zoneName: "Notes"),
                       .init(containerIdentifier: "iCloud.heynotes.tests", environment: .development, zoneName: "")] {
            await #expect(throws: SyncActivationError.invalidConfiguration) { try await inspector.inspect(configuration: config) }
        }
        #expect(count.value == 0)
    }

    @Test func completePaginationPreservesLatestHeadersAndAcceptsAnEmptyFinalTail() async throws {
        let a = SyncEntityIdentity(kind: .notebook, id: UUID()), b = SyncEntityIdentity(kind: .page, id: UUID())
        let c = SyncEntityIdentity(kind: .card, id: UUID()), blob = "blob." + String(repeating: "b", count: 64)
        let latest = header(a, tag: "latest")
        let client = FixtureInspectionTransport(pages: [page([.entity(header(a)), .entity(header(b))], token: "one", more: true),
            page([.entity(latest), .entity(header(c, deleted: true)), .blob(name: blob, changeTag: "blob-tag")],
                 deletions: [.init(name: b.recordName, recordType: SyncCloudRecordPlan.entityType)], token: "two", more: true),
            page(token: "two")])
        let inspector = SyncCloudActivationInspector(notifications: NotificationCenter(), transport: { _ in client })
        let result = try await inspector.inspect(configuration: configuration)
        #expect(result.entities.count == 2 && result.entities[a]?.changeTag == "latest")
        #expect(result.entities[c]?.deleted == true && result.deletedEntities == [b] && result.blobNames == [blob])
        #expect(result.scope == (try scope()))
        let requested = await client.requestedTokens
        #expect(requested == [nil, Data("one".utf8), Data("two".utf8)])
        try result.validate()
    }

    @Test func changedAccountsAndAccountNotificationsInvalidateTheWholeInspection() async throws {
        let different = FixtureInspectionTransport(accounts: ["account-a", "account-b"], pages: [page()])
        let inspector = SyncCloudActivationInspector(notifications: NotificationCenter(), transport: { _ in different })
        await #expect(throws: SyncActivationError.accountChanged) { try await inspector.inspect(configuration: configuration) }
        let center = NotificationCenter()
        let notified = FixtureInspectionTransport(pages: [page()], notificationCenter: center)
        let observer = SyncCloudActivationInspector(notifications: center, transport: { _ in notified })
        await #expect(throws: SyncActivationError.accountChanged) { try await observer.inspect(configuration: configuration) }
        let unavailable = FixtureInspectionTransport(accounts: [], pages: [page()])
        let offline = SyncCloudActivationInspector(transport: { _ in unavailable })
        await #expect(throws: SyncActivationError.accountUnavailable) { try await offline.inspect(configuration: configuration) }
    }

    @Test func partialMalformedAmbiguousAndNonprogressingStreamsNeverYieldACompletedBaseline() async throws {
        let id = SyncEntityIdentity(kind: .page, id: UUID()), value = SyncRemoteHeader.entity(header(.init(kind: .page, id: UUID())))
        let streams: [[SyncRemoteInspectionPage]] = [
            [page(token: "same", more: true), page(token: "same", more: true)],
            [page([value, value])],
            [page([.entity(header(id))], deletions: [.init(name: id.recordName, recordType: SyncCloudRecordPlan.entityType)])],
            [page(deletions: [.init(name: "future.record", recordType: "UnknownFutureType")])],
            [page([.entity(header(id, tag: ""))])],
            [page(token: "first", more: true)] // Fixture runs out: equivalent to an interrupted fetch.
        ]
        for pages in streams {
            let client = FixtureInspectionTransport(pages: pages)
            let inspector = SyncCloudActivationInspector(notifications: NotificationCenter(), transport: { _ in client })
            await #expect(throws: (any Error).self) { try await inspector.inspect(configuration: configuration) }
        }
        let client = FixtureInspectionTransport(pages: [page()])
        let inspector = SyncCloudActivationInspector(transport: { _ in client })
        let task = Task { try await inspector.inspect(configuration: configuration) }; task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func locallyPreparedRecordsCannotMasqueradeAsServerHeaders() throws {
        let identity = SyncEntityIdentity(kind: .notebook, id: UUID())
        let record = CKRecord(recordType: SyncCloudRecordPlan.entityType, recordID: .init(recordName: identity.recordName, zoneID: configuration.zoneID))
        record["hnSchema"] = 1 as NSNumber; record["hnKind"] = "notebook" as NSString
        record["hnRevision"] = UUID().uuidString.lowercased() as NSString
        record["hnDeleted"] = 0 as NSNumber; record["hnPayloadHash"] = String(repeating: "a", count: 64) as NSString
        #expect(throws: SyncActivationError.unsupportedRecord) { try SyncRemoteHeader(record: record, zone: configuration.zoneID) }
        #expect(throws: SyncActivationError.unsupportedRecord) { try SyncRemoteHeader.identity(identity.recordName.uppercased()) }
    }

    @Test func reviewKeepsBothLibrariesAndRejectsStaleLocalRemoteOrSessionInputs() throws {
        let localOnly = SyncEntityIdentity(kind: .notebook, id: UUID()), shared = SyncEntityIdentity(kind: .page, id: UUID())
        let remoteOnly = SyncEntityIdentity(kind: .deck, id: UUID()), localDelete = SyncEntityIdentity(kind: .card, id: UUID())
        let remoteDelete = SyncEntityIdentity(kind: .page, id: UUID()), hardDelete = SyncEntityIdentity(kind: .review, id: UUID())
        let lease = SyncStateLease(libraryID: UUID(), scope: try scope(), generation: UUID(), storeGeneration: UUID())
        let local = SyncActivationLocalInventory(libraryID: lease.libraryID, identities: [localOnly, shared, remoteDelete],
            pending: [localDelete: .init(operation: .delete, revision: UUID()), localOnly: .init(operation: .upsert, revision: UUID())])
        let remote = SyncRemoteBaseline(id: UUID(), scope: lease.scope, entities: [shared: header(shared), remoteOnly: header(remoteOnly),
            localDelete: header(localDelete), remoteDelete: header(remoteDelete, deleted: true)], blobNames: [], deletedEntities: [hardDelete], finalToken: Data([1]))
        let review = try SyncActivationReview.make(local: local, remote: remote, enrollmentID: UUID(), lease: lease)
        let decisions = Dictionary(uniqueKeysWithValues: review.items.map { ($0.identity, $0.disposition) })
        #expect(decisions[localOnly] == .localOnlyNeedsReview && decisions[shared] == .sharedIdentityNeedsComparison)
        #expect(decisions[remoteOnly] == .remoteOnlyNeedsDownload && decisions[localDelete] == .localDeletionNeedsReview)
        #expect(decisions[remoteDelete] == .remoteDeletionNeedsReview && decisions[hardDelete] == .remoteDeletionNeedsReview)
        try review.validate(local: local, remote: remote, lease: lease)
        let changed = SyncActivationLocalInventory(libraryID: lease.libraryID, identities: local.identities,
            pending: [localDelete: .init(operation: .delete, revision: UUID())])
        #expect(throws: SyncActivationError.staleReview) { try review.validate(local: changed, remote: remote, lease: lease) }
        let renewed = SyncStateLease(libraryID: lease.libraryID, scope: lease.scope, generation: UUID(), storeGeneration: lease.storeGeneration)
        #expect(throws: SyncActivationError.staleReview) { try review.validate(local: local, remote: remote, lease: renewed) }
        let changedRemote = SyncRemoteBaseline(id: remote.id, scope: remote.scope, entities: [shared: header(shared, tag: "changed")],
            blobNames: [], deletedEntities: [], finalToken: remote.finalToken)
        #expect(throws: SyncActivationError.staleReview) { try review.validate(local: local, remote: changedRemote, lease: lease) }
    }

    @Test func freshLocalInventoryAndStateReviewAreReadOnlyAndObserveRealEdits() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("ActivationReview-\(UUID())").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true), c = container.mainContext
        let book = Notebook(title: "Before"); c.insert(book); try c.save()
        let state = try SyncStateStore(directory: root), libraryID = try await state.registerLibrary()
        let lease = try await state.bind(scope(), libraryID: libraryID)
        let source = SyncInitialEnrollmentStore(modelContainer: container, libraryID: libraryID)
        _ = try await state.prepareInitialEnrollment(using: source, lease: lease)
        let remote = SyncRemoteBaseline(id: UUID(), scope: lease.scope, entities: [:], blobNames: [], deletedEntities: [], finalToken: Data([1]))
        let before = try await source.activationInventory()
        let review = try await state.prepareActivationReview(using: source, remote: remote, lease: lease)
        #expect(review.items.count == 1 && review.items.first?.disposition == .localOnlyNeedsReview)
        let unchanged = try await source.activationInventory()
        #expect(unchanged.fingerprint == before.fingerprint && !c.hasChanges)
        book.title = "Edited during cloud inspection"; try c.saveRecordingSyncChanges()
        let after = try await source.activationInventory()
        #expect(after.fingerprint != before.fingerprint)
        #expect(throws: SyncActivationError.staleReview) { try review.validate(local: after, remote: remote, lease: lease) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SyncChange>()) == 1)
        try await state.close()
        withExtendedLifetime(container) {}
    }

    @Test func wrongScopeIncompleteBaselineAndUnenrolledLibrariesCannotBeReviewed() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("ActivationGuards-\(UUID())").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let state = try SyncStateStore(directory: root), id = try await state.registerLibrary()
        let lease = try await state.bind(scope(), libraryID: id), source = SyncInitialEnrollmentStore(modelContainer: container, libraryID: id)
        let remote = SyncRemoteBaseline(id: UUID(), scope: lease.scope, entities: [:], blobNames: [], deletedEntities: [], finalToken: Data([1]))
        await #expect(throws: SyncActivationError.enrollmentRequired) { try await state.prepareActivationReview(using: source, remote: remote, lease: lease) }
        _ = try await state.prepareInitialEnrollment(using: source, lease: lease)
        let wrong = SyncRemoteBaseline(id: UUID(), scope: try scope(account: "account-b"), entities: [:], blobNames: [], deletedEntities: [], finalToken: Data([1]))
        await #expect(throws: SyncActivationError.scopeMismatch) { try await state.prepareActivationReview(using: source, remote: wrong, lease: lease) }
        let incomplete = SyncRemoteBaseline(id: UUID(), scope: lease.scope, entities: [:], blobNames: [], deletedEntities: [], finalToken: Data())
        await #expect(throws: SyncActivationError.incompleteBaseline) { try await state.prepareActivationReview(using: source, remote: incomplete, lease: lease) }
        try await state.close()
    }
}

private final class InspectionFactoryCount: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private actor FixtureInspectionTransport: SyncCloudInspectionTransport {
    private var accounts: [String]
    private var pages: [SyncRemoteInspectionPage]
    private let notificationCenter: NotificationCenter?
    private(set) var requestedTokens: [Data?] = []
    init(accounts: [String] = ["account-a", "account-a"], pages: [SyncRemoteInspectionPage], notificationCenter: NotificationCenter? = nil) {
        self.accounts = accounts; self.pages = pages; self.notificationCenter = notificationCenter
    }
    func accountRecordName() throws -> String {
        guard !accounts.isEmpty else { throw SyncActivationError.accountUnavailable }
        return accounts.removeFirst()
    }
    func page(after token: Data?) throws -> SyncRemoteInspectionPage {
        guard !pages.isEmpty else { throw SyncActivationError.incompleteBaseline }
        requestedTokens.append(token)
        notificationCenter?.post(name: .CKAccountChanged, object: nil)
        return pages.removeFirst()
    }
}
