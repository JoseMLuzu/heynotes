import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct SyncUploadStagingTests {
    @Test func snapshotsKeepOldBytesAndMetadataWhileNewChangesRemainPending() async throws {
        let f = try UploadFixture(); defer { f.cleanup() }
        let context = f.container.mainContext
        let book = Notebook(title: "Notes"), page = NotePage(pageIndex: 0)
        context.insert(book); context.insert(page); book.pages = [page]
        page.bookmarkTitle = "Original"; page.drawingFilePath = "ink.drawing"; page.pdfFilePath = "source.pdf"; page.pdfPageIndex = 0
        let ink = Data("old editable ink".utf8), pdf = Data("original PDF".utf8), image = Data([4, 8, 12])
        try await f.storage.write(ink, to: "ink.drawing"); try await f.storage.write(pdf, to: "source.pdf")
        try await f.storage.write(image, to: "image.png")
        var a = PageElement(kind: .image, rect: .init(x: 0, y: 0, width: 10, height: 10)); a.imagePath = "image.png"
        var b = a; b.id = UUID(); page.objectsData = try PageElementsCodec.encode([a, b])
        try context.saveRecordingSyncChanges()
        let key = SyncEntityIdentity(kind: .page, id: page.id).recordName
        let metadata = SyncUploadMetadataStore(modelContainer: f.container)
        let plan = try await metadata.capture(key)
        let captured = try await f.storage.captureSyncSources(plan)
        try await f.storage.write(Data("new ink".utf8), to: "ink.drawing")
        try FileManager.default.removeItem(at: try await f.storage.fileURL(for: "source.pdf"))
        page.bookmarkTitle = "Newer"; try context.saveRecordingSyncChanges()
        let package = try await f.staging.prepare(captured)
        let reads = await f.staging.statistics()
        #expect(reads.readPasses == 3) // The shared image file is streamed once for both image roles.
        print("PERFORMANCE shared_asset_roles=4 full_source_read_passes=\(reads.readPasses)")
        #expect(package.manifest.revision == plan.revision && package.manifest.assets.count == 4)
        let drawing = try #require(package.manifest.assets.first { $0.role == "drawing" })
        #expect(try Data(contentsOf: package.assetURL(drawing)) == ink)
        let originalPDF = try #require(package.manifest.assets.first { $0.role == "pdf" })
        #expect(try Data(contentsOf: package.assetURL(originalPDF)) == pdf)
        let images = package.manifest.assets.filter { $0.role.hasPrefix("image.") }
        #expect(images.count == 2 && images[0].sha256 == images[1].sha256)
        let snapshot = try JSONDecoder().decode(BackupManifest.SavedPage.self, from: Data(contentsOf: try #require(package.metadataURL)))
        #expect(snapshot.bookmark == "Original")
        #expect(try !SyncChangeJournal.acknowledge(key, revision: plan.revision, in: context))
        let newer = try await metadata.capture(key)
        #expect(newer.revision != plan.revision) // Reusing the metadata actor cannot return cached values.
        let reopened = SyncUploadStagingStore(root: f.stagingRoot)
        let loaded = try await reopened.load(package.manifest.id)
        #expect(loaded.manifest.revision == plan.revision)
        let assets = loaded.cloudAssets()
        #expect(assets["drawing"]?.fileURL == loaded.assetURL(drawing))
        #expect(assets.values.allSatisfy { $0.fileURL?.path.hasPrefix(f.stagingRoot.path) == true })
        #expect(!String(decoding: try Data(contentsOf: loaded.directory.appendingPathComponent("manifest.json")), as: UTF8.self).contains(f.root.path))
        try await reopened.discard(loaded.manifest.id)
        #expect(try await f.storage.read("ink.drawing") == Data("new ink".utf8))
        #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) > 0)
    }

    @Test func concurrentCopiesUseIndependentOffsetsAndKeepPackagesIndependent() async throws {
        let f = try UploadFixture(); defer { f.cleanup() }
        let bytes = Data(repeating: 0xAB, count: 3 * 1_048_576 + 17)
        try await f.storage.write(bytes, to: "large.pdf")
        let captured = try await f.storage.captureSyncSources(f.plan([.init(role: "pdf", path: "large.pdf")]))
        let other = SyncUploadStagingStore(root: f.stagingRoot)
        async let first = f.staging.prepare(captured)
        async let second = other.prepare(captured)
        let (a, b) = try await (first, second)
        #expect(a.manifest.id != b.manifest.id && a.manifest.assets[0].sha256 == b.manifest.assets[0].sha256)
        #expect(try Data(contentsOf: a.assetURL(a.manifest.assets[0])) == bytes)
        try await f.staging.discard(a.manifest.id)
        #expect(try Data(contentsOf: b.assetURL(b.manifest.assets[0])) == bytes)
        #expect(try await f.storage.read("large.pdf") == bytes)
    }

    @Test func requiredMissingUnsafeAndSymlinkedSourcesFailWithoutPublishing() async throws {
        let f = try UploadFixture(); defer { f.cleanup() }
        for path in ["missing.drawing", "../outside", "/absolute/path"] {
            await #expect(throws: (any Error).self) {
                try await f.storage.captureSyncSources(f.plan([.init(role: "drawing", path: path)]))
            }
        }
        let source = f.root.appendingPathComponent("outside.pdf")
        try Data([1]).write(to: source)
        try FileManager.default.createSymbolicLink(at: f.documents.appendingPathComponent("link.pdf"), withDestinationURL: source)
        await #expect(throws: (any Error).self) {
            try await f.storage.captureSyncSources(f.plan([.init(role: "pdf", path: "link.pdf")]))
        }
        let blank = try await f.storage.captureSyncSources(f.plan([.init(role: "drawing", path: "blank.drawing", allowsMissing: true)]))
        let prepared = try await f.staging.prepare(blank)
        #expect(prepared.manifest.assets.isEmpty)
        #expect(try await f.staging.packageIDs() == [prepared.manifest.id])
    }

    @Test func inPlaceSourceMutationAndCancellationNeverPublishPartialPackages() async throws {
        let f = try UploadFixture(); defer { f.cleanup() }
        try await f.storage.write(Data(repeating: 4, count: 4096), to: "drawing")
        let captured = try await f.storage.captureSyncSources(f.plan([.init(role: "drawing", path: "drawing")]))
        // Production uses atomic replacement; reject unsupported in-place writes instead of
        // mixing revisions if a future caller violates that storage contract.
        let handle = try FileHandle(forWritingTo: await f.storage.fileURL(for: "drawing"))
        try handle.truncate(atOffset: 0); try handle.close()
        await #expect(throws: (any Error).self) { try await f.staging.prepare(captured) }
        #expect(try await f.staging.packageIDs().isEmpty)
        let blank = try await f.storage.captureSyncSources(f.plan([]))
        let cancelled = Task { try await f.staging.prepare(blank) }; cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await f.staging.packageIDs().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stagingRoot.path).isEmpty)
    }

    @Test func damagedPackagesAndAssetSymlinksAreRetainedUntilExplicitDiscard() async throws {
        let f = try UploadFixture(); defer { f.cleanup() }
        try await f.storage.write(Data([1, 2, 3]), to: "ink")
        let captured = try await f.storage.captureSyncSources(f.plan([.init(role: "drawing", path: "ink")]))
        let prepared = try await f.staging.prepare(captured)
        let asset = prepared.assetURL(prepared.manifest.assets[0])
        try FileManager.default.removeItem(at: asset)
        try Data([9, 9, 9]).write(to: asset)
        await #expect(throws: (any Error).self) { try await f.staging.load(prepared.manifest.id) }
        #expect(try await f.staging.packageIDs().contains(prepared.manifest.id))
        try FileManager.default.removeItem(at: asset)
        try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: await f.storage.fileURL(for: "ink"))
        await #expect(throws: (any Error).self) { try await f.staging.load(prepared.manifest.id) }
        try await f.staging.discard(prepared.manifest.id)
        #expect(try await f.storage.read("ink") == Data([1, 2, 3]))
        let partial = f.stagingRoot.appendingPathComponent(".building-\(UUID())")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: false)
        #expect(try await f.staging.packageIDs().isEmpty)
        #expect(FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func capturedCardImagesAndDeletedEntitiesHaveCompleteVersionedPlans() async throws {
        let f = try UploadFixture(); defer { f.cleanup() }
        let context = f.container.mainContext, deck = StudyDeck(title: "Review")
        let card = Flashcard(question: "Q", answer: "A")
        context.insert(deck); context.insert(card); deck.cards = [card]
        card.questionImagePath = "question.png"; card.answerImagePath = "answer.png"
        try await f.storage.write(Data([7, 8]), to: "question.png")
        try await f.storage.write(Data([9, 10]), to: "answer.png")
        try context.saveRecordingSyncChanges()
        let key = SyncEntityIdentity(kind: .card, id: card.id).recordName
        let metadata = SyncUploadMetadataStore(modelContainer: f.container)
        let plan = try await metadata.capture(key)
        let captured = try await f.storage.captureSyncSources(plan)
        let prepared = try await f.staging.prepare(captured)
        #expect(Set(prepared.manifest.assets.map(\.role)) == Set(["question", "answer"]))
        context.delete(card); try context.saveRecordingSyncChanges()
        let deletion = try await metadata.capture(key)
        let empty = try await f.storage.captureSyncSources(deletion)
        let tombstone = try await f.staging.prepare(empty)
        #expect(tombstone.manifest.operation == .delete && tombstone.metadataURL == nil && tombstone.cloudAssets().isEmpty)
        _ = try await f.staging.load(tombstone.manifest.id)
        #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) > 0) // Preparation is not a server acknowledgement.
    }
}

@MainActor private final class UploadFixture {
    let root = URL.temporaryDirectory.appendingPathComponent("SyncUploadTests-\(UUID())", isDirectory: true)
    let documents: URL
    let stagingRoot: URL
    let storage: DrawingStorage
    let staging: SyncUploadStagingStore
    let container: ModelContainer
    init() throws {
        documents = root.appendingPathComponent("Documents", isDirectory: true)
        stagingRoot = root.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        storage = DrawingStorage(root: documents); staging = SyncUploadStagingStore(root: stagingRoot)
        container = try PersistenceController.makeContainer(inMemory: true)
    }
    func plan(_ sources: [SyncAssetSource]) -> SyncUploadPlan {
        SyncUploadPlan(identity: .init(kind: .page, id: UUID()), revision: UUID(), operation: .upsert,
                       metadata: Data("{}".utf8), sources: sources)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
