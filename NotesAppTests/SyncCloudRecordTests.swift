import CloudKit
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct SyncCloudRecordTests {
    @Test func allEntityKindsKeepPermanentIDsRelationshipsAndStudyHistory() async throws {
        let f = try CloudWireFixture(); defer { f.cleanup() }
        let c = f.container.mainContext
        let folder = Folder(title: "Biology"), book = Notebook(title: "Cells")
        let section = NotebookSection(title: "Unit 1", sortIndex: 2), page = NotePage(pageIndex: 4)
        let deck = StudyDeck(title: "Membranes", notebookID: book.id)
        let card = Flashcard(question: "Function?", answer: "Selective transport", sourceNotebookID: book.id, sourcePageID: page.id)
        let review = ReviewRecord(rating: "good", reviewedAt: .now, nextReviewAt: .now.addingTimeInterval(86400), intervalSeconds: 86400)
        c.insert(folder); c.insert(book); c.insert(section); c.insert(page); c.insert(deck); c.insert(card); c.insert(review)
        book.folder = folder; book.sections = [section]; book.pages = [page]; page.section = section
        deck.cards = [card]; card.reviews = [review]
        folder.isFavorite = true; book.isFavorite = true; page.bookmarkTitle = "Exam"
        try c.saveRecordingSyncChanges()
        let identities: [SyncEntityIdentity] = [.init(kind: .folder, id: folder.id), .init(kind: .notebook, id: book.id),
            .init(kind: .section, id: section.id), .init(kind: .page, id: page.id), .init(kind: .deck, id: deck.id),
            .init(kind: .card, id: card.id), .init(kind: .review, id: review.id)]
        for identity in identities {
            let package = try await f.prepare(identity)
            let plan = try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone)
            #expect(plan.entity.recordID.recordName == identity.recordName)
            #expect(plan.entity.recordID.zoneID == f.zone && plan.entity.recordType == SyncCloudRecordPlan.entityType)
            #expect(plan.entity["hnDeleted"] as? Int == 0)
            let payload = try f.payload(plan)
            #expect(payload.version == 1 && payload.identity == identity && payload.revision == package.manifest.revision)
            let original = try Data(contentsOf: #require(package.metadataURL))
            #expect(payload.metadata == original, "Records without local file references preserve all scalar metadata.")
            #expect(plan.blobs.isEmpty)
        }
        #expect(try c.fetchCount(FetchDescriptor<SyncChange>()) == 7)
        #expect(!c.hasChanges)
    }

    @Test func largePagePayloadReplacesAllFilePathsAndSharesBlobIdentities() async throws {
        let f = try CloudWireFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, book = Notebook(title: "Rich"), page = NotePage(pageIndex: 0)
        c.insert(book); c.insert(page); book.pages = [page]
        let sourceInk = Data(repeating: 7, count: 1_048_576)
        var image = PageElement(kind: .image, rect: .init(x: 10, y: 20, width: 100, height: 50))
        image.imagePath = "Notebooks/local-photo.png"
        var text = PageElement(kind: .text, rect: .init(x: 30, y: 80, width: 100, height: 60))
        text.fontFilePath = "Fonts/local-font.ttf"; text.originalInk = sourceInk
        text.originalInkAnchorX = 30; text.originalInkAnchorY = 75; text.text = "Keep this exact text"
        page.objectsData = try PageElementsCodec.encode([image, text])
        page.drawingFilePath = "Notebooks/editable.drawing"; page.pdfFilePath = "Sources/lecture.pdf"; page.pdfPageIndex = 2
        for path in [image.imagePath!, text.fontFilePath!, page.drawingFilePath!, page.pdfFilePath!] {
            try await f.storage.write(Data([1, 2, 3, 4]), to: path)
        }
        try c.saveRecordingSyncChanges()
        let identity = SyncEntityIdentity(kind: .page, id: page.id)
        let package = try await f.prepare(identity)
        let plan = try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone)
        let payload = try f.payload(plan)
        #expect(payload.assets.count == 4 && plan.blobs.count == 1)
        let remote = try JSONDecoder().decode(BackupManifest.SavedPage.self, from: payload.metadata)
        let objects = try PageElementsCodec.decode(remote.objects)
        let name = try #require(plan.blobs.first?.recordID.recordName)
        #expect(remote.drawing == name && remote.pdf == name && remote.pdfIndex == 2)
        #expect(objects[0].imagePath == name && objects[1].fontFilePath == name)
        #expect(objects[1].originalInk == sourceInk && objects[1].originalInkAnchorY == 75)
        #expect(objects[1].text == text.text)
        #expect((try Data(contentsOf: #require((plan.entity["hnPayload"] as? CKAsset)?.fileURL))).count > 1_048_576)
        let blobURL = try #require((plan.blobs[0]["hnAsset"] as? CKAsset)?.fileURL)
        #expect(blobURL.path.hasPrefix(package.directory.path + "/"))
        #expect(try Data(contentsOf: blobURL) == Data([1, 2, 3, 4]))
        #expect(page.drawingFilePath == "Notebooks/editable.drawing" && page.objectsData != remote.objects)
        let anotherZone = CKRecordZone.ID(zoneName: "AnotherPrivateZone")
        let reopened = SyncUploadStagingStore(root: f.stagingRoot)
        let fields = Dictionary(uniqueKeysWithValues: plan.recordsToSave.map {
            ($0.recordID.recordName, SyncRecordSystemFields.encode($0))
        })
        let based = try await reopened.cloudRecordPlan(package.manifest.id, zone: f.zone, systemFields: fields)
        #expect(based.entity.recordID == plan.entity.recordID && based.blobs[0].recordID == plan.blobs[0].recordID)
        #expect(based.entity["hnPayload"] as? CKAsset != nil)
        let again = try await reopened.cloudRecordPlan(package.manifest.id, zone: anotherZone)
        #expect(again.entity.recordID.recordName == plan.entity.recordID.recordName)
        #expect(again.entity.recordID.zoneID == anotherZone)
        #expect((again.entity["hnPayload"] as? CKAsset)?.fileURL == (plan.entity["hnPayload"] as? CKAsset)?.fileURL)
        page.pageIndex = 9; book.title = "Renamed"; try c.saveRecordingSyncChanges()
        let updated = try await f.prepare(identity)
        let next = try await f.staging.cloudRecordPlan(updated.manifest.id, zone: f.zone)
        #expect(next.entity.recordID == plan.entity.recordID && next.revision != plan.revision)
        #expect(next.blobs[0].recordID == plan.blobs[0].recordID)
        #expect(try !SyncChangeJournal.acknowledge(identity.recordName, revision: plan.revision, in: c))
    }

    @Test func cardImagesUseBlobIDsAndDeleteProducesOnlyRecoverableTombstone() async throws {
        let f = try CloudWireFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, deck = StudyDeck(title: "Test"), card = Flashcard(question: "Q", answer: "A")
        c.insert(deck); c.insert(card); deck.cards = [card]
        card.questionImagePath = "Cards/question.png"; card.answerImagePath = "Cards/answer.png"
        try await f.storage.write(Data([1]), to: card.questionImagePath!)
        try await f.storage.write(Data([2]), to: card.answerImagePath!)
        try c.saveRecordingSyncChanges()
        let identity = SyncEntityIdentity(kind: .card, id: card.id), package = try await f.prepare(identity)
        let plan = try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone)
        let value = try JSONDecoder().decode(BackupManifest.SavedCard.self, from: f.payload(plan).metadata)
        #expect(value.questionImage?.hasPrefix("blob.") == true && value.answerImage?.hasPrefix("blob.") == true)
        let fields = SyncRecordSystemFields.encode(plan.entity)
        c.delete(card); try c.saveRecordingSyncChanges()
        let deletion = try await f.prepare(identity)
        let tombstone = try await f.staging.cloudRecordPlan(deletion.manifest.id, zone: f.zone,
            systemFields: [identity.recordName: fields])
        #expect(tombstone.recordsToSave.count == 1 && tombstone.blobs.isEmpty)
        #expect(tombstone.entity.recordID == plan.entity.recordID && tombstone.entity["hnDeleted"] as? Int == 1)
        #expect(tombstone.entity["hnPayload"] == nil && tombstone.entity["hnBlobs"] == nil)
        #expect(Set(["hnPayload", "hnPayloadHash", "hnBlobs"]).isSubset(of: Set(tombstone.entity.changedKeys())))
        #expect(try await f.storage.read("Cards/question.png") == Data([1]))
        #expect(try c.fetchCount(FetchDescriptor<SyncChange>()) > 0)
    }

    @Test func systemFieldsRoundTripExcludesUserDataAndRejectsOtherIdentityZoneOrType() throws {
        let zone = CKRecordZone.ID(zoneName: "LocalOnly"), id = CKRecord.ID(recordName: "notebook.test", zoneID: zone)
        let record = CKRecord(recordType: SyncCloudRecordPlan.entityType, recordID: id)
        record["privateText"] = "Never archive this" as NSString
        let data = SyncRecordSystemFields.encode(record)
        let restored = try SyncRecordSystemFields.decode(data, expecting: id, type: record.recordType)
        #expect(restored.recordID == id && restored.allKeys().isEmpty)
        for wrong in [CKRecord.ID(recordName: "other", zoneID: zone), CKRecord.ID(recordName: id.recordName, zoneID: .init(zoneName: "Other"))] {
            #expect(throws: (any Error).self) { try SyncRecordSystemFields.decode(data, expecting: wrong, type: record.recordType) }
        }
        #expect(throws: (any Error).self) { try SyncRecordSystemFields.decode(data, expecting: id, type: "OtherType") }
        for damaged in [Data(), Data([1, 2, 3]), Data(repeating: 0, count: 1_048_577)] {
            #expect(throws: (any Error).self) { try SyncRecordSystemFields.decode(damaged, expecting: id, type: record.recordType) }
        }
    }

    @Test func malformedMetadataAndIncompleteOrUnexpectedRolesNeverProducePlans() async throws {
        let f = try CloudWireFixture(); defer { f.cleanup() }
        let identity = SyncEntityIdentity(kind: .notebook, id: UUID())
        let wrong = BackupManifest.SavedNotebook(id: UUID(), title: "Wrong", createdAt: .now, updatedAt: .now,
                                               cover: "blue", trashedAt: nil, favorite: false, folderID: nil)
        for bytes in [Data([1, 2]), try JSONEncoder().encode(wrong)] {
            let captured = try await f.storage.captureSyncSources(.init(identity: identity, revision: UUID(), operation: .upsert, metadata: bytes, sources: []))
            let package = try await f.staging.prepare(captured)
            await #expect(throws: (any Error).self) { try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone) }
            #expect(try await f.staging.packageIDs().contains(package.manifest.id))
        }
        let book = Notebook(title: "Wrong roles"), page = NotePage(pageIndex: 0)
        f.container.mainContext.insert(book); f.container.mainContext.insert(page); book.pages = [page]
        page.drawingFilePath = "ink"; try await f.storage.write(Data([1]), to: "ink")
        var image = PageElement(kind: .image, rect: .init(x: 0, y: 0, width: 10, height: 10)); image.imagePath = "ink"
        page.objectsData = try PageElementsCodec.encode([image])
        let data = try JSONEncoder().encode(BackupManifest.SavedPage(page))
        for roles in [[SyncAssetSource(role: "drawing", path: "ink")],
                      [.init(role: "drawing", path: "ink"), .init(role: "image.\(image.id.uuidString.lowercased())", path: "ink"), .init(role: "unknown", path: "ink")]] {
            let plan = SyncUploadPlan(identity: .init(kind: .page, id: page.id), revision: UUID(), operation: .upsert, metadata: data, sources: roles)
            let captured = try await f.storage.captureSyncSources(plan), package = try await f.staging.prepare(captured)
            await #expect(throws: (any Error).self) { try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone) }
        }
    }

    @Test func corruptionCancellationAndUnsupportedFileSizesPreservePreparedPackages() async throws {
        let f = try CloudWireFixture(); defer { f.cleanup() }
        let c = f.container.mainContext, book = Notebook(title: "Keep"), page = NotePage(pageIndex: 0)
        c.insert(book); c.insert(page); book.pages = [page]; try c.saveRecordingSyncChanges()
        let package = try await f.prepare(.init(kind: .page, id: page.id))
        let plan = try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone)
        await #expect(throws: (any Error).self) {
            try await f.staging.cloudRecordPlan(package.manifest.id, zone: CKRecordZone.ID.default)
        }
        let url = try #require((plan.entity["hnPayload"] as? CKAsset)?.fileURL)
        try FileManager.default.removeItem(at: url); try Data([0]).write(to: url)
        await #expect(throws: (any Error).self) { try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone) }
        let cancelled = Task { try await f.staging.cloudRecordPlan(package.manifest.id, zone: f.zone) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let oversized = f.root.appendingPathComponent("oversized")
        #expect(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let file = try FileHandle(forWritingTo: oversized)
        try file.truncate(atOffset: SyncCloudRecordPlan.maximumAssetBytes + 1); try file.close()
        try await f.storage.copyFile(from: oversized, to: "large.pdf")
        page.pdfFilePath = "large.pdf"; page.pdfPageIndex = 0; try c.saveRecordingSyncChanges()
        let largePackage = try await f.prepare(.init(kind: .page, id: page.id))
        await #expect(throws: (any Error).self) { try await f.staging.cloudRecordPlan(largePackage.manifest.id, zone: f.zone) }
        #expect(try await f.staging.packageIDs().contains(largePackage.manifest.id))
        #expect(try c.fetchCount(FetchDescriptor<SyncChange>()) > 0)
    }
}

@MainActor private struct CloudWireFixture {
    let root = URL.temporaryDirectory.appendingPathComponent("CloudWire-\(UUID())")
    let container: ModelContainer
    let storage: DrawingStorage
    let staging: SyncUploadStagingStore
    let stagingRoot: URL
    let zone = CKRecordZone.ID(zoneName: "LocalPreparationTests")
    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        stagingRoot = root.appendingPathComponent("Packages")
        staging = SyncUploadStagingStore(root: stagingRoot)
    }
    func prepare(_ identity: SyncEntityIdentity) async throws -> PreparedSyncUpload {
        let plan = try await SyncUploadMetadataStore(modelContainer: container).capture(identity.recordName)
        let captured = try await storage.captureSyncSources(plan)
        return try await staging.prepare(captured)
    }
    func payload(_ plan: SyncCloudRecordPlan) throws -> SyncCloudPayload {
        let url = try #require((plan.entity["hnPayload"] as? CKAsset)?.fileURL)
        return try JSONDecoder().decode(SyncCloudPayload.self, from: Data(contentsOf: url))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
