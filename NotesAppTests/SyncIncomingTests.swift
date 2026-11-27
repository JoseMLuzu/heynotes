import Foundation
import SwiftData
import CloudKit
import Testing
@testable import NotesAppCore

@MainActor struct SyncIncomingTests {
    @Test func receivedWireFilesSurviveSourceDeletionReopenAndDoNotChangeLocalData() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (package, plan) = try await f.prepare()
        let inputs = try f.inputs(plan), id = UUID(), inbox = try f.inbox()
        let pending = try f.container.mainContext.fetch(FetchDescriptor<SyncChange>()).map(\.revision)
        let before = f.page.updatedAt
        try await f.staging.discard(package.manifest.id) // Pinned descriptors retain temporary download bytes.
        let receipt = try await inbox.receive(inputs, deliveryID: id)
        #expect(receipt.recordCount == inputs.count && receipt.libraryID == f.libraryID && receipt.scopeKey == f.scope.key)
        await inbox.close()
        let reopened = try f.inbox()
        let entity = try await reopened.entity(plan.identity.recordName, in: id)
        #expect(entity.payload?.identity.id == f.page.id && entity.payload?.revision == plan.revision)
        let snapshot = try JSONDecoder().decode(BackupManifest.SavedPage.self, from: try #require(entity.payload?.metadata))
        #expect(snapshot.trashedAt == f.date && snapshot.notebookID == f.book.id && snapshot.pdfIndex == 0)
        #expect(try Data(contentsOf: #require(entity.assetFiles["drawing"])) == f.ink)
        #expect(try Data(contentsOf: #require(entity.assetFiles["pdf"])) == f.pdf)
        #expect(f.page.updatedAt == before && f.page.drawingFilePath == "ink.drawing")
        #expect(try f.container.mainContext.fetch(FetchDescriptor<SyncChange>()).map(\.revision) == pending)
        #expect(try await f.storage.read("ink.drawing") == f.ink)
        let manifest = try Data(contentsOf: f.incoming.appendingPathComponent(id.uuidString + "/manifest.json"))
        #expect(!String(decoding: manifest, as: UTF8.self).contains(f.root.path))
        await reopened.close()
    }

    @Test func missingBlobsWaitForAnotherDurableDeliveryAndSharedRolesResolveOnce() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), inputs = try f.inputs(plan), inbox = try f.inbox(), id = UUID()
        _ = try await inbox.receive(inputs.filter { $0.record.type == SyncCloudRecordPlan.entityType }, deliveryID: id)
        await #expect(throws: SyncIncomingError.missingAsset) { try await inbox.entity(plan.identity.recordName, in: id) }
        #expect(f.book.pages.count == 1 && f.page.drawingFilePath == "ink.drawing")
        _ = try await inbox.receive(inputs.filter { $0.record.type == SyncCloudRecordPlan.blobType }, deliveryID: UUID())
        let entity = try await inbox.entity(plan.identity.recordName, in: id)
        let images = entity.assetFiles.filter { $0.key.hasPrefix("image.") }
        #expect(images.count == 2 && Set(images.values).count == 1)
        await inbox.close()
    }

    @Test func completeInterruptedDeliveryCanPublishAfterRestartWithoutDownloadFiles() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (package, plan) = try await f.prepare(), id = UUID(), inputs = try f.inputs(plan)
        let inbox = try f.inbox { if case .beforePublish = $0 { throw IncomingFixture.Failure() } }
        await #expect(throws: IncomingFixture.Failure.self) { try await inbox.receive(inputs, deliveryID: id) }
        #expect(try await inbox.inventory().received.isEmpty)
        #expect(try await inbox.inventory().interrupted == [id])
        await inbox.close(); try await f.staging.discard(package.manifest.id)
        let reopened = try f.inbox()
        let receipt = try await reopened.resume(id)
        #expect(receipt.deliveryID == id && receipt.recordCount == inputs.count)
        #expect(try await reopened.inventory().interrupted.isEmpty)
        let entity = try await reopened.entity(plan.identity.recordName, in: id)
        #expect(try Data(contentsOf: #require(entity.assetFiles["drawing"])) == f.ink)
        await reopened.close()
    }

    @Test func incompleteDeliveryRetainsIntentAndRetryResumesButCannotReplaceIt() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), id = UUID(), inputs = try f.inputs(plan)
        let inbox = try f.inbox { if case .manifestSaved = $0 { throw IncomingFixture.Failure() } }
        await #expect(throws: IncomingFixture.Failure.self) { try await inbox.receive(inputs, deliveryID: id) }
        await inbox.close()
        let reopened = try f.inbox()
        await #expect(throws: SyncIncomingError.incomplete) { try await reopened.resume(id) }
        let deletion = SyncIncomingDeletion(name: plan.identity.recordName, type: SyncCloudRecordPlan.entityType)
        await #expect(throws: SyncIncomingError.deliveryMismatch) { try await reopened.receive([], deletions: [deletion], deliveryID: id) }
        #expect(try await reopened.inventory().interrupted == [id])
        _ = try await reopened.receive(inputs, deliveryID: id)
        let again = try await reopened.receive(Array(inputs.reversed()), deliveryID: id)
        #expect(again.deliveryID == id)
        #expect(try await reopened.inventory().received == [id])
        await reopened.close()
    }

    @Test func failureAfterPublicationIsRecoverableAndNeverAcknowledgesLocalJournal() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), id = UUID(), inputs = try f.inputs(plan)
        let inbox = try f.inbox { if case .published = $0 { throw IncomingFixture.Failure() } }
        await #expect(throws: IncomingFixture.Failure.self) { try await inbox.receive(inputs, deliveryID: id) }
        #expect(try await inbox.inventory().received == [id]); await inbox.close()
        let reopened = try f.inbox()
        #expect(try await reopened.receive(inputs, deliveryID: id).deliveryID == id)
        #expect(try f.container.mainContext.fetch(FetchDescriptor<SyncChange>()).contains { $0.entityID == f.page.id })
        await reopened.close()
    }

    @Test func corruptedSourceAndStoredCopiesNeverBecomeApplyableOrGetPurged() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), inputs = try f.inputs(plan), inbox = try f.inbox(), id = UUID()
        _ = try await inbox.receive(inputs, deliveryID: id)
        let record = try #require(inputs.first { $0.record.type == SyncCloudRecordPlan.blobType }?.record)
        let url = f.incoming.appendingPathComponent(id.uuidString + "/" + (try #require(record.filename)))
        try Data([0xFF]).write(to: url, options: .atomic)
        await #expect(throws: SyncIncomingError.integrity) { try await inbox.load(id) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try await inbox.inventory().received == [id])
        // A fresh malformed source is retained only as interrupted, never published.
        let bad = f.root.appendingPathComponent("bad"); try Data(repeating: 0, count: Int(record.byteCount!)).write(to: bad)
        let input = try SyncIncomingInput(record: record, sourceURL: bad), secondID = UUID()
        await #expect(throws: SyncIncomingError.integrity) { try await inbox.receive([input], deliveryID: secondID) }
        #expect(try await inbox.inventory().interrupted == [secondID])
        #expect(try await f.storage.read("ink.drawing") == f.ink)
        await inbox.close()
    }

    @Test func bindingsExclusiveWriterSymlinksAndCancellationFailWithoutLocalMutation() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), inputs = try f.inputs(plan), inbox = try f.inbox()
        #expect(throws: SyncStateError.alreadyOpen) { try f.inbox() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await inbox.receive(inputs, deliveryID: UUID())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await inbox.inventory().received.isEmpty); await inbox.close()
        let other = try SyncAccountScope(containerIdentifier: f.scope.containerIdentifier, environment: .development,
            accountRecordName: "other-account", zone: f.scope.zoneID)
        #expect(throws: SyncIncomingError.scopeMismatch) { try SyncIncomingStore(directory: f.incoming, libraryID: f.libraryID, scope: other) }
        #expect(throws: SyncIncomingError.scopeMismatch) { try SyncIncomingStore(directory: f.incoming, libraryID: UUID(), scope: f.scope) }
        let reopened = try f.inbox(), id = UUID()
        _ = try await reopened.receive(inputs, deliveryID: id)
        let record = try #require(inputs.first { $0.record.filename != nil }?.record)
        let path = f.incoming.appendingPathComponent(id.uuidString + "/" + (try #require(record.filename)))
        try FileManager.default.removeItem(at: path)
        let outside = f.root.appendingPathComponent("outside"); try Data([7]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
        await #expect(throws: SyncIncomingError.unsafePath) { try await reopened.load(id) }
        #expect(try Data(contentsOf: outside) == Data([7]))
        await reopened.close()
    }

    @Test func sdkBoundaryRejectsLocalProposalsAndHardDeletionsStayQueuedOnly() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), inbox = try f.inbox(), id = UUID()
        await #expect(throws: SyncActivationError.unsupportedRecord) { try await inbox.receive(fetched: plan.recordsToSave, deliveryID: id) }
        #expect(try await inbox.inventory().received.isEmpty)
        let record = SyncIncomingRecord(name: plan.identity.recordName, type: SyncCloudRecordPlan.entityType, changeTag: "offline-tombstone",
            revision: UUID(), tombstone: true, sha256: nil, byteCount: nil, blobs: [])
        let input = try SyncIncomingInput(record: record, sourceURL: nil)
        let deletion = SyncIncomingDeletion(name: "blob." + String(repeating: "a", count: 64), type: SyncCloudRecordPlan.blobType)
        _ = try await inbox.receive([input], deletions: [deletion], deliveryID: id)
        let entity = try await inbox.entity(record.name, in: id)
        #expect(entity.record.tombstone && entity.payload == nil && entity.assetFiles.isEmpty)
        #expect(try await inbox.load(id).deletions == [deletion])
        #expect(f.book.pages.count == 1 && f.page.trashedAt == f.date)
        await #expect(throws: SyncIncomingError.invalidRecord) {
            try await inbox.receive([input], deletions: [.init(name: record.name, type: record.type)], deliveryID: UUID())
        }
        await inbox.close()
    }

    @Test func everyEntityKindRetainsWireIdentityReferencesAndAssetsWithoutApplying() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        _ = try await f.prepare()
        let context = f.container.mainContext
        let folder = Folder(title: "Course"), section = NotebookSection(title: "Cells", sortIndex: 0)
        let deck = StudyDeck(title: "Study", notebookID: f.book.id)
        let card = Flashcard(question: "Q", answer: "A", sourceNotebookID: f.book.id, sourcePageID: f.page.id)
        card.questionImagePath = "image.png"
        let review = ReviewRecord(rating: "hard", reviewedAt: f.date, nextReviewAt: f.date, intervalSeconds: 600)
        for model: any PersistentModel in [folder, section, deck, card, review] { context.insert(model) }
        f.book.folder = folder; f.book.sections = [section]; f.page.section = section; deck.cards = [card]; card.reviews = [review]
        try context.saveRecordingSyncChanges()
        let inbox = try f.inbox(), metadata = SyncUploadMetadataStore(modelContainer: f.container)
        let identities: [SyncEntityIdentity] = [.init(kind: .folder, id: folder.id), .init(kind: .notebook, id: f.book.id),
            .init(kind: .section, id: section.id), .init(kind: .page, id: f.page.id), .init(kind: .deck, id: deck.id),
            .init(kind: .card, id: card.id), .init(kind: .review, id: review.id)]
        for identity in identities {
            let plan = try await metadata.capture(identity.recordName), captured = try await f.storage.captureSyncSources(plan)
            let staged = try await f.staging.prepare(captured), wire = try await f.staging.cloudRecordPlan(staged.manifest.id, zone: f.scope.zoneID)
            let id = UUID()
            _ = try await inbox.receive(f.inputs(wire), deliveryID: id)
            let incoming = try await inbox.entity(identity.recordName, in: id)
            #expect(incoming.payload?.identity == identity && incoming.payload?.revision == plan.revision)
        }
        #expect(try context.fetchCount(FetchDescriptor<Notebook>()) == 1)
        #expect(card.sourcePageID == f.page.id && review.flashcard?.id == card.id)
        await inbox.close()
    }

    @Test func validHashWithInvalidPayloadAndDamagedManifestRemainUnavailable() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), inbox = try f.inbox(), id = UUID()
        let url = try #require((plan.entity["hnPayload"] as? CKAsset)?.fileURL)
        let original = try JSONDecoder().decode(SyncCloudPayload.self, from: Data(contentsOf: url))
        let bad = SyncCloudPayload(version: 77, identity: original.identity, revision: original.revision, metadata: original.metadata, assets: original.assets)
        let bytes = try JSONEncoder().encode(bad), source = f.root.appendingPathComponent("bad-payload.json")
        try bytes.write(to: source)
        let record = SyncIncomingRecord(name: plan.identity.recordName, type: SyncCloudRecordPlan.entityType, changeTag: "offline-fixture",
            revision: original.revision, tombstone: false, sha256: SyncIncomingFiles.digest(bytes), byteCount: UInt64(bytes.count),
            blobs: Array(Set(original.assets.map(\.recordName))).sorted())
        let input = try SyncIncomingInput(record: record, sourceURL: source)
        await #expect(throws: SyncIncomingError.invalidRecord) { try await inbox.receive([input], deliveryID: id) }
        #expect(try await inbox.inventory().received.isEmpty)
        let manifestURL = f.incoming.appendingPathComponent("receiving-" + id.uuidString + "/manifest.json")
        try Data([0, 1, 2]).write(to: manifestURL, options: .atomic)
        await #expect(throws: SyncIncomingError.integrity) { try await inbox.resume(id) }
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        await inbox.close()
    }

    @Test func payloadValidationRejectsPathsWrongRevisionsDuplicateRolesAndUnsupportedVersions() async throws {
        let f = try IncomingFixture(); defer { f.cleanup() }
        let (_, plan) = try await f.prepare(), record = try #require(f.inputs(plan).first { $0.record.type == SyncCloudRecordPlan.entityType }?.record)
        let url = try #require((plan.entity["hnPayload"] as? CKAsset)?.fileURL)
        let original = try JSONDecoder().decode(SyncCloudPayload.self, from: Data(contentsOf: url))
        var page = try JSONDecoder().decode(BackupManifest.SavedPage.self, from: original.metadata)
        page.drawing = "../../local.drawing"
        let variants = [
            SyncCloudPayload(version: 2, identity: original.identity, revision: original.revision, metadata: original.metadata, assets: original.assets),
            .init(version: 1, identity: original.identity, revision: UUID(), metadata: original.metadata, assets: original.assets),
            .init(version: 1, identity: original.identity, revision: original.revision, metadata: try JSONEncoder().encode(page), assets: original.assets),
            .init(version: 1, identity: original.identity, revision: original.revision, metadata: original.metadata, assets: original.assets + [original.assets[0]])
        ]
        for value in variants { #expect(throws: (any Error).self) { try SyncIncomingPayloadValidation.validate(value, for: record) } }
        let records = (0..<6).map { index -> SyncIncomingRecord in
            let hash = SyncIncomingFiles.digest(Data([UInt8(index)]))
            return .init(name: "blob." + hash, type: SyncCloudRecordPlan.blobType, changeTag: "offline", revision: nil,
                         tombstone: false, sha256: hash, byteCount: 40_000_000, blobs: [])
        }
        let manifest = SyncIncomingManifest(id: UUID(), libraryID: f.libraryID, scopeKey: f.scope.key, records: records, deletions: [])
        #expect(throws: SyncIncomingError.tooLarge) { try manifest.validate(libraryID: f.libraryID, scope: f.scope) }
    }
}

@MainActor private final class IncomingFixture {
    struct Failure: Error {}
    let root = URL.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Incoming-\(UUID())")
    let libraryID = UUID(), date = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let storage: DrawingStorage
    let staging: SyncUploadStagingStore
    let book = Notebook(title: "Original"), page = NotePage(pageIndex: 0)
    let scope: SyncAccountScope
    let ink = Data("editable source ink".utf8), pdf = Data("original PDF".utf8)
    var incoming: URL { root.appendingPathComponent("Incoming") }
    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        staging = SyncUploadStagingStore(root: root.appendingPathComponent("Uploads"))
        scope = try SyncAccountScope(containerIdentifier: "iCloud.heynotes.tests", environment: .development,
            accountRecordName: "offline-incoming-fixture", zone: .init(zoneName: "Notes"))
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
        page.drawingFilePath = "ink.drawing"; page.pdfFilePath = "source.pdf"; page.pdfPageIndex = 0; page.trashedAt = date
        var a = PageElement(kind: .image, rect: .init(x: 0, y: 0, width: 50, height: 50)); a.imagePath = "image.png"
        var b = a; b.id = UUID(); page.objectsData = try PageElementsCodec.encode([a, b])
        try container.mainContext.saveRecordingSyncChanges()
    }
    func prepare() async throws -> (PreparedSyncUpload, SyncCloudRecordPlan) {
        try await storage.write(ink, to: "ink.drawing"); try await storage.write(pdf, to: "source.pdf")
        try await storage.write(Data([1, 2, 3, 4]), to: "image.png")
        let metadata = SyncUploadMetadataStore(modelContainer: container)
        let plan = try await metadata.capture(SyncEntityIdentity(kind: .page, id: page.id).recordName)
        let captured = try await storage.captureSyncSources(plan), package = try await staging.prepare(captured)
        return (package, try await staging.cloudRecordPlan(package.manifest.id, zone: scope.zoneID))
    }
    func inbox(progress: @escaping @Sendable (SyncIncomingStore.Progress) throws -> Void = { _ in }) throws -> SyncIncomingStore {
        try SyncIncomingStore(directory: incoming, libraryID: libraryID, scope: scope, progress: progress)
    }
    // Explicit offline normalized fixtures: never manufacture a server change tag inside CKRecord.
    func inputs(_ plan: SyncCloudRecordPlan) throws -> [SyncIncomingInput] {
        try plan.recordsToSave.map { value in
            let blob = value.recordType == SyncCloudRecordPlan.blobType
            let url = try #require((value[blob ? "hnAsset" : "hnPayload"] as? CKAsset)?.fileURL)
            let hash = try #require(value[blob ? "hnHash" : "hnPayloadHash"] as? String)
            let record = SyncIncomingRecord(name: value.recordID.recordName, type: value.recordType, changeTag: "offline-fixture",
                revision: blob ? nil : plan.revision, tombstone: false, sha256: hash,
                byteCount: try SyncSourceFile(url: url).byteCount, blobs: (value["hnBlobs"] as? [String]) ?? [])
            return try SyncIncomingInput(record: record, sourceURL: url)
        }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
