import Foundation
import SwiftData
import CryptoKit
import Testing
@testable import NotesAppCore

@MainActor struct LibraryBackupTests {
    @Test func importedFontAssetsAndRecoveryAnchorsSurviveBackupAndIndependentRestore() async throws {
        let f = try BackupFixture(); defer { f.cleanup() }; try await f.seed()
        let page = try #require(f.container.mainContext.fetch(FetchDescriptor<NotePage>()).first { $0.id == f.pageID })
        var objects = try PageElementsCodec.decode(page.objectsData)
        let bytes = Data("user-owned font bytes".utf8)
        objects[0].fontName = "MyHandwriting"; objects[0].fontFilePath = "Fonts/personal.ttf"
        objects[0].originalInkAnchorX = 12; objects[0].originalInkAnchorY = 26
        page.objectsData = try PageElementsCodec.encode(objects)
        try f.container.mainContext.saveRecordingSyncChanges()
        try await f.storage.write(bytes, to: "Fonts/personal.ttf")
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let prepared = try await service.prepareRestore(from: url); defer { Task { await service.discard(prepared) } }
        let target = try BackupFixture(); defer { target.cleanup() }
        _ = try await LibraryBackupService(container: target.container, storage: target.storage).restore(prepared)
        let restored = try #require(target.container.mainContext.fetch(FetchDescriptor<NotePage>()).first { $0.id == f.pageID })
        let text = try #require(PageElementsCodec.decode(restored.objectsData).first)
        let path = try #require(text.fontFilePath)
        #expect(path.hasPrefix("Restored/") && path.hasSuffix("/Fonts/personal.ttf"))
        #expect(try await target.storage.read(path) == bytes)
        #expect(text.fontName == "MyHandwriting" && text.originalInkAnchorX == 12 && text.originalInkAnchorY == 26)
        // Required font data cannot be silently omitted from an otherwise valid archive.
        var files: [(String, Data)] = []
        for file in prepared.files where file.path != "Fonts/personal.ttf" {
            files.append((file.path, try await f.storage.read(file.path)))
        }
        let incomplete = f.root.appendingPathComponent("missing-font.heynotesbackup")
        try rawArchive(prepared.manifest, files: files).write(to: incomplete)
        await #expect(throws: (any Error).self) { try await service.prepareRestore(from: incomplete) }
    }

    @Test func completeLibraryRoundTripRetainsIDsFilesTrashAndStudyAfterDiskReopen() async throws {
        let fixture = try BackupFixture(); defer { fixture.cleanup() }
        try await fixture.seed()
        let service = LibraryBackupService(container: fixture.container, storage: fixture.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let prepared = try await service.prepareRestore(from: url); defer { Task { await service.discard(prepared) } }
        #expect(prepared.manifest.notebooks.count == 1 && prepared.manifest.pages.count == 2)
        #expect(prepared.files.contains { $0.path.hasSuffix(".backup") })
        #expect(prepared.files.contains { $0.path.contains("retained") })
        let target = try BackupFixture(); defer { target.cleanup() }
        let importer = LibraryBackupService(container: target.container, storage: target.storage)
        let result = try await importer.restore(prepared)
        #expect(result.notebooks == 1 && result.pages == 2 && result.cards == 2)
        let reopened = try PersistenceController.makeContainer(storeURL: target.storeURL)
        let context = reopened.mainContext
        let book = try #require(context.fetch(FetchDescriptor<Notebook>()).first)
        #expect(book.id == fixture.bookID && book.coverStyle == .mathematicsCover && book.isFavorite)
        #expect(book.createdAt == fixture.date && book.updatedAt == fixture.date)
        #expect(book.folder?.parent?.title == "University" && book.folder?.color == .lavender)
        #expect(try context.fetch(FetchDescriptor<Folder>()).contains { $0.trashedAt == fixture.date })
        let page = try #require(book.pages.first { $0.id == fixture.pageID })
        #expect(page.section?.title == "Cells" && page.bookmarkTitle == "Exam" && page.pdfRightMargin == 180)
        #expect(page.pageWidth == 600 && page.pageHeight == 800 && page.pdfPageIndex == 3)
        let path = try #require(page.drawingFilePath)
        #expect(path.hasPrefix("Restored/"))
        #expect(try await target.storage.read(path) == fixture.ink)
        #expect(try await target.storage.read(path + ".backup") == Data([1, 2]))
        #expect(try await target.storage.read(try #require(page.pdfFilePath)) == fixture.pdf)
        let elements = try PageElementsCodec.decode(page.objectsData)
        #expect(elements.first?.text == "A cell" && elements.first?.originalInk == Data([7, 8]))
        #expect(try await target.storage.read(try #require(elements.last?.imagePath)) == fixture.image)
        let implicit = try #require(book.pages.first { $0.id != fixture.pageID })
        #expect(try await target.storage.read(try #require(implicit.drawingFilePath)) == Data([11]))
        let prefix = path.components(separatedBy: "/Notebooks/")[0]
        #expect(try await target.storage.read(prefix + "/Notebooks/Deleted/retained.drawing") == Data([42]))
        let cards = try context.fetch(FetchDescriptor<Flashcard>())
        let card = try #require(cards.first { $0.id == fixture.cardID })
        #expect(try await target.storage.read(try #require(card.questionImagePath)) == Data([70, 71]))
        #expect(try await target.storage.read(try #require(card.answerImagePath)) == Data([80, 81]))
        #expect(card.deck?.notebookID == book.id && card.sourcePageID == page.id && card.sourceNotebookID == book.id)
        #expect(card.intervalSeconds == 259200 && card.repetitionCount == 2 && card.lapseCount == 1)
        #expect(card.nextReviewAt == fixture.date.addingTimeInterval(259200) && card.reviews.count == 1)
        #expect(card.reviews.first?.id == fixture.reviewID && card.reviews.first?.schedulerVersion == 1)
        #expect(cards.contains { $0.trashedAt == fixture.date && $0.sourcePageID == fixture.missingPageID })
        #expect(try await fixture.storage.read(fixture.drawingPath) == fixture.ink)
        withExtendedLifetime(reopened) {}
    }

    @Test func restoringIntoExistingLibraryAddsIndependentCopiesAndRemapsAllLinks() async throws {
        let f = try BackupFixture(); defer { f.cleanup() }; try await f.seed()
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let prepared = try await service.prepareRestore(from: url); defer { Task { await service.discard(prepared) } }
        _ = try await service.restore(prepared)
        let context = ModelContext(f.container)
        let books = try context.fetch(FetchDescriptor<Notebook>())
        #expect(books.count == 2)
        let original = try #require(books.first { $0.id == f.bookID }), copy = try #require(books.first { $0.id != f.bookID })
        #expect(original.updatedAt == f.date && copy.updatedAt == f.date)
        #expect(copy.folder?.id != original.folder?.id && copy.folder?.parent?.id != original.folder?.parent?.id)
        let page = try #require(copy.pages.first { $0.pdfFilePath != nil })
        #expect(page.id != f.pageID && page.section?.notebook?.id == copy.id)
        #expect(page.pdfFilePath != original.pages.first { $0.id == f.pageID }?.pdfFilePath)
        let cards = try context.fetch(FetchDescriptor<Flashcard>())
        let card = try #require(cards.first { $0.id != f.cardID && $0.sourceNotebookID == copy.id && $0.trashedAt == nil })
        #expect(card.sourcePageID == page.id && card.deck?.notebookID == copy.id)
        #expect(card.reviews.first?.id != f.reviewID && card.reviews.first?.flashcard?.id == card.id)
        #expect(try await f.storage.read(f.drawingPath) == f.ink)
        #expect(try await f.storage.read(try #require(page.drawingFilePath)) == f.ink)
    }

    @Test func invalidArchivesNeverMutateLibraryAndRejectUnsafeOrDuplicatePaths() async throws {
        let f = try BackupFixture(); defer { f.cleanup() }; try await f.seed()
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let original = try Data(contentsOf: url)
        var damaged = original; damaged[damaged.count - 1] ^= 1
        var manifest = try await BackupMetadataStore(modelContainer: f.container).capture()
        var inputs = [Data(original.prefix(20)), damaged]
        inputs.append(try rawArchive(manifest, files: [])) // Required files are absent.
        manifest.pages = []; manifest.sections = []
        inputs.append(try rawArchive(manifest, files: [("../outside", Data([1]))]))
        inputs.append(try rawArchive(manifest, files: [("A/file", Data([1])), ("a/file", Data([2]))]))
        manifest.formatVersion = 3; inputs.append(try rawArchive(manifest, files: []))
        for (index, bytes) in inputs.enumerated() {
            let source = f.root.appendingPathComponent("invalid-\(index).heynotesbackup"); try bytes.write(to: source)
            await #expect(throws: (any Error).self) { try await service.prepareRestore(from: source) }
        }
        #expect(try f.container.mainContext.fetchCount(FetchDescriptor<Notebook>()) == 1)
        #expect(try await f.storage.read(f.drawingPath) == f.ink)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("outside").path))
    }

    @Test func metadataSaveFailureRollsBackOnlyRestoreAndRemovesOnlyItsNewFiles() async throws {
        let source = try BackupFixture(); defer { source.cleanup() }; try await source.seed()
        let exporter = LibraryBackupService(container: source.container, storage: source.storage)
        let url = try await exporter.exportLibrary(); defer { Task { await exporter.discardExport(url) } }
        let prepared = try await exporter.prepareRestore(from: url); defer { Task { await exporter.discard(prepared) } }
        let target = try BackupFixture(); defer { target.cleanup() }; try await target.seed()
        let book = try #require(target.container.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        book.title = "Unsaved editor title"
        let importer = LibraryBackupService(container: target.container, storage: target.storage, save: { _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        await #expect(throws: (any Error).self) { try await importer.restore(prepared) }
        #expect(book.title == "Unsaved editor title" && target.container.mainContext.hasChanges)
        let persisted = ModelContext(target.container)
        #expect(try persisted.fetchCount(FetchDescriptor<Notebook>()) == 1)
        #expect(try persisted.fetchCount(FetchDescriptor<Flashcard>()) == 2)
        #expect(try await target.storage.read(target.drawingPath) == target.ink)
        let restores = target.documents.appendingPathComponent("Restored")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: restores.path).isEmpty) ?? true)
    }

    @Test func missingFilesSymlinksAndStagingTamperingFailSafely() async throws {
        let f = try BackupFixture(); defer { f.cleanup() }; try await f.seed()
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let prepared = try await service.prepareRestore(from: url); defer { Task { await service.discard(prepared) } }
        try Data([99]).write(to: prepared.directory.appendingPathComponent("Assets/" + f.drawingPath))
        await #expect(throws: (any Error).self) { try await service.restore(prepared) }
        #expect(try f.container.mainContext.fetchCount(FetchDescriptor<Notebook>()) == 1)
        let link = f.documents.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.root)
        await #expect(throws: (any Error).self) { try await service.exportLibrary() }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.removeItem(at: f.documents.appendingPathComponent(f.drawingPath))
        await #expect(throws: (any Error).self) { try await service.exportLibrary() }
    }

    @Test func cyclesDuplicateIDsEmptyLibrariesAndCancellationAreHandled() async throws {
        let f = try BackupFixture(); defer { f.cleanup() }
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let prepared = try await service.prepareRestore(from: url)
        #expect(prepared.files.isEmpty && prepared.manifest.pages.isEmpty)
        _ = try await service.restore(prepared); await service.discard(prepared)
        #expect(!FileManager.default.fileExists(atPath: prepared.directory.path))
        var manifest = prepared.manifest
        let id = UUID()
        let folder = BackupManifest.SavedFolder(id: id, title: "Cycle", createdAt: .now, color: nil, favorite: false, trashedAt: nil, parentID: id)
        manifest.folders = [folder]
        #expect(throws: (any Error).self) { try BackupValidation.manifest(manifest) }
        manifest.folders = [folder, folder]
        #expect(throws: (any Error).self) { try BackupValidation.manifest(manifest) }
        let cancelled = Task { try await service.exportLibrary() }; cancelled.cancel()
        await #expect(throws: (any Error).self) { try await cancelled.value }
    }

    @Test func legacyVersionOneAndMissingCardImagesAreValidated() async throws {
        let f = try BackupFixture(); defer { f.cleanup() }; try await f.seed()
        var manifest = try await BackupMetadataStore(modelContainer: f.container).capture()
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let prepared = try await service.prepareRestore(from: url); defer { Task { await service.discard(prepared) } }
        var files: [(String, Data)] = []
        for file in prepared.files { files.append((file.path, try await f.storage.read(file.path))) }
        let missing = f.root.appendingPathComponent("missing-card-image.heynotesbackup")
        try rawArchive(manifest, files: files.filter { $0.0 != "Study/Images/front.png" }).write(to: missing)
        await #expect(throws: (any Error).self) { try await service.prepareRestore(from: missing) }
        manifest.formatVersion = 1
        for i in manifest.cards.indices { manifest.cards[i].questionImage = nil; manifest.cards[i].answerImage = nil }
        let legacy = f.root.appendingPathComponent("legacy.heynotesbackup")
        try rawArchive(manifest, files: files).write(to: legacy)
        let old = try await service.prepareRestore(from: legacy); defer { Task { await service.discard(old) } }
        let target = try BackupFixture(); defer { target.cleanup() }
        _ = try await LibraryBackupService(container: target.container, storage: target.storage).restore(old)
        #expect(try target.container.mainContext.fetchCount(FetchDescriptor<Flashcard>()) == 2)
        #expect(try target.container.mainContext.fetch(FetchDescriptor<Flashcard>()).allSatisfy { $0.questionImagePath == nil && $0.answerImagePath == nil })
    }

    private func rawArchive(_ manifest: BackupManifest, files: [(String, Data)]) throws -> Data {
        let data = try JSONEncoder().encode(manifest)
        var result = BackupArchiveIO.magic + BackupArchiveIO.integer(UInt64(data.count)) + Data(SHA256.hash(data: data)) + data
        result += BackupArchiveIO.integer(UInt64(files.count))
        for (path, content) in files {
            let name = Data(path.utf8)
            result += BackupArchiveIO.integer(UInt64(name.count)) + name + BackupArchiveIO.integer(UInt64(content.count))
            result += Data(SHA256.hash(data: content)) + content
        }
        return result
    }
}

@MainActor private final class BackupFixture {
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let container: ModelContainer
    let storage: DrawingStorage
    var documents: URL { root.appendingPathComponent("Documents") }
    var storeURL: URL { root.appendingPathComponent("library.store") }
    let bookID = UUID(), pageID = UUID(), cardID = UUID(), reviewID = UUID(), missingPageID = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let ink = Data([3, 4, 5]), pdf = Data("original-pdf".utf8), image = Data(repeating: 17, count: 2_100_000)
    var drawingPath: String { DrawingStorage.path(notebook: bookID, page: pageID) }
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("library.store"))
        storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func seed() async throws {
        let context = container.mainContext
        let parent = Folder(title: "University"), folder = Folder(title: "Biology", parent: parent)
        folder.color = .lavender; folder.isFavorite = true
        let trashed = Folder(title: "Old term"); trashed.trashedAt = date
        for item in [parent, folder, trashed] { context.insert(item) }
        let book = Notebook(title: "Cells", folder: folder, id: bookID, now: date)
        book.coverStyle = .mathematicsCover; book.isFavorite = true; context.insert(book)
        let section = NotebookSection(title: "Cells", sortIndex: 0); context.insert(section); section.notebook = book
        let page = NotePage(pageIndex: 0, id: pageID, now: date), blank = NotePage(pageIndex: 1, now: date)
        context.insert(page); context.insert(blank); book.pages = [page, blank]; page.section = section
        page.drawingFilePath = drawingPath; page.bookmarkTitle = "Exam"
        page.pdfFilePath = "Notebooks/\(bookID)/Sources/source.pdf"; page.pdfPageIndex = 3
        page.pageWidth = 600; page.pageHeight = 800; page.pdfRightMargin = 180
        var text = PageElement(kind: .text, rect: CGRect(x: 20, y: 30, width: 200, height: 60))
        text.text = "A cell"; text.originalInk = Data([7, 8])
        var photo = PageElement(kind: .image, rect: CGRect(x: 20, y: 100, width: 200, height: 150))
        photo.imagePath = "Notebooks/\(bookID)/Images/photo.jpg"
        page.objectsData = try PageElementsCodec.encode([text, photo])
        let deck = StudyDeck(title: "Biology", notebookID: bookID, now: date); context.insert(deck)
        let card = Flashcard(question: "Unit of life?", answer: "A cell", sourceNotebookID: bookID, sourcePageID: pageID, id: cardID, now: date)
        card.questionImagePath = "Study/Images/front.png"; card.answerImagePath = "Study/Images/back.png"
        card.intervalSeconds = 259200; card.repetitionCount = 2; card.lapseCount = 1
        card.nextReviewAt = date.addingTimeInterval(259200); context.insert(card); card.deck = deck
        let removed = Flashcard(question: "Deleted source", answer: "Preserve", sourceNotebookID: bookID, sourcePageID: missingPageID, now: date)
        removed.trashedAt = date; context.insert(removed); removed.deck = deck
        let review = ReviewRecord(rating: "good", reviewedAt: date, nextReviewAt: card.nextReviewAt, intervalSeconds: 259200, id: reviewID)
        context.insert(review); review.flashcard = card
        try context.save()
        try await storage.write(Data([1, 2]), to: drawingPath); try await storage.write(ink, to: drawingPath)
        try await storage.write(Data([70, 71]), to: card.questionImagePath!); try await storage.write(Data([80, 81]), to: card.answerImagePath!)
        try await storage.write(pdf, to: page.pdfFilePath!); try await storage.write(image, to: photo.imagePath!)
        try await storage.write(Data([11]), to: DrawingStorage.path(notebook: bookID, page: blank.id))
        try await storage.write(Data([42]), to: "Notebooks/Deleted/retained.drawing")
    }
}
