import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct StudyImageMigrationTests {
    @Test func realV6DiskStoreMigratesWithoutChangingInkIDsOrReviewProgress() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Library.store"), pageID = UUID(), cardID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let path = "Notebooks/existing/Page.drawing", bytes = Data([17, 27, 37])
        try await storage.write(bytes, to: path)
        try seedV6(url: url, pageID: pageID, cardID: cardID, now: now, path: path)
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = container.mainContext
        let card = try #require(context.fetch(FetchDescriptor<Flashcard>()).first)
        let page = try #require(context.fetch(FetchDescriptor<NotePage>()).first)
        #expect(card.id == cardID && page.id == pageID && card.sourcePageID == pageID)
        #expect(card.sourceNotebookID == page.notebook?.id && card.deck?.notebookID == page.notebook?.id)
        #expect(card.repetitionCount == 4 && card.lapseCount == 1 && card.intervalSeconds == 604800)
        #expect(card.nextReviewAt == now.addingTimeInterval(604800) && card.reviews.count == 1)
        #expect(card.questionImagePath == nil && card.answerImagePath == nil)
        #expect(page.drawingFilePath == path && page.section?.title == "Unit 1" && page.notebook?.folder?.title == "Biology")
        #expect(try await storage.read(path) == bytes)
        card.questionImagePath = "Study/Images/front.png"; try context.save()
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Flashcard>()).first?.questionImagePath == "Study/Images/front.png")
        withExtendedLifetime((container, reopened)) {}
    }
    private func seedV6(url: URL, pageID: UUID, cardID: UUID, now: Date, path: String) throws {
        let schema = Schema(versionedSchema: NotesSchemaV6.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let c = container.mainContext; c.autosaveEnabled = false
        let folder = NotesSchemaV6.Folder(title: "Biology")
        let book = NotesSchemaV6.Notebook(title: "Cells", folder: folder, now: now)
        let page = NotesSchemaV6.NotePage(pageIndex: 0, id: pageID, now: now)
        let section = NotesSchemaV6.NotebookSection(title: "Unit 1", sortIndex: 0)
        let deck = NotesSchemaV6.StudyDeck(title: "Review", notebookID: book.id, now: now)
        let card = NotesSchemaV6.Flashcard(question: "Unit of life?", answer: "Cell", sourceNotebookID: book.id, sourcePageID: pageID, id: cardID, now: now)
        c.insert(folder); c.insert(book); c.insert(page); c.insert(section); c.insert(deck); c.insert(card)
        book.pages = [page]; section.notebook = book; page.section = section; page.drawingFilePath = path; card.deck = deck
        card.repetitionCount = 4; card.lapseCount = 1; card.intervalSeconds = 604800; card.nextReviewAt = now.addingTimeInterval(604800)
        let review = NotesSchemaV6.ReviewRecord(rating: "good", reviewedAt: now, nextReviewAt: card.nextReviewAt, intervalSeconds: 604800)
        c.insert(review); review.flashcard = card; try c.save()
    }
}
