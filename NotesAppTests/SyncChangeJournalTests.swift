import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct SyncChangeJournalTests {
    @Test func editsCoalesceAcrossReopenAndOldAcknowledgementsKeepNewerWork() throws {
        try withStore { url in
            let id = UUID(), key = SyncEntityIdentity(kind: .notebook, id: id).recordName
            var firstRevision: UUID!
            do {
                let container = try PersistenceController.makeContainer(storeURL: url), context = container.mainContext
                let book = Notebook(title: "First", id: id); context.insert(book)
                try context.saveRecordingSyncChanges()
                firstRevision = try #require(context.fetch(FetchDescriptor<SyncChange>()).first).revision
                book.title = "Second"; try context.saveRecordingSyncChanges()
            }
            let container = try PersistenceController.makeContainer(storeURL: url), context = container.mainContext
            let rows = try context.fetch(FetchDescriptor<SyncChange>())
            #expect(rows.count == 1)
            let row = try #require(rows.first), revision = row.revision
            #expect(row.recordName == key && row.revision != firstRevision)
            #expect(try !SyncChangeJournal.acknowledge(key, revision: firstRevision, in: context))
            for _ in 0..<3 { try context.saveRecordingSyncChanges() }
            #expect(row.revision == revision)
            #expect(try SyncChangeJournal.acknowledge(key, revision: revision, in: context))
            try context.saveRecordingSyncChanges()
            #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 0)
            #expect(try context.fetch(FetchDescriptor<Notebook>()).first?.title == "Second")
        }
    }

    @Test func rollbackAndUncommittedChangesNeverCreateASeparateJournalTransaction() throws {
        try withStore { url in
            let container = try PersistenceController.makeContainer(storeURL: url), context = container.mainContext
            let book = Notebook(title: "Committed"); context.insert(book); try context.save()
            book.title = "Pending"
            try SyncChangeJournal.recordPendingChanges(in: context)
            #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 1)
            let observer = ModelContext(container)
            #expect(try observer.fetchCount(FetchDescriptor<SyncChange>()) == 0)
            #expect(try observer.fetch(FetchDescriptor<Notebook>()).first?.title == "Committed")
            context.rollback()
            #expect(book.title == "Committed")
            #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 0)
        }
    }

    @Test func cascadeDeletesRetainTombstonesForEveryUserEntity() throws {
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let folder = Folder(title: "Course"), book = Notebook(title: "Notes"), page = NotePage(pageIndex: 0)
        let section = NotebookSection(title: "Unit", sortIndex: 0), deck = StudyDeck(title: "Study")
        let card = Flashcard(question: "Q", answer: "A")
        let review = ReviewRecord(rating: "good", reviewedAt: .now, nextReviewAt: .now, intervalSeconds: 60)
        context.insert(folder); context.insert(book); context.insert(page); context.insert(section)
        context.insert(deck); context.insert(card); context.insert(review)
        book.folder = folder; book.pages = [page]; book.sections = [section]; section.pages = [page]
        deck.cards = [card]; card.reviews = [review]
        try context.saveRecordingSyncChanges()
        #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 7)
        context.delete(book); context.delete(deck)
        try context.saveRecordingSyncChanges()
        let rows = try context.fetch(FetchDescriptor<SyncChange>())
        #expect(rows.count == 7)
        #expect(rows.filter { $0.operationRawValue == "delete" }.count == 6)
        #expect(rows.first { $0.entityID == folder.id }?.operationRawValue == "upsert")
        #expect(try context.fetchCount(FetchDescriptor<NotePage>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReviewRecord>()) == 0)
    }

    @Test func identityUsesEntityKindAndUUIDWhileBulkEditsStayCoalesced() throws {
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let book = Notebook(title: "Bulk"), id = book.id
        context.insert(book)
        for index in 0..<210 {
            let page = NotePage(pageIndex: index, id: index == 0 ? id : UUID())
            context.insert(page); book.pages.append(page)
        }
        try context.saveRecordingSyncChanges()
        let first = try context.fetch(FetchDescriptor<SyncChange>())
        #expect(first.count == 211 && Set(first.map(\.recordName)).count == 211)
        #expect(first.contains { $0.entityID == id && $0.kindRawValue == "page" })
        #expect(first.contains { $0.entityID == id && $0.kindRawValue == "notebook" })
        for page in book.pages { page.pageIndex += 1 }
        book.title = "Renamed"
        try context.saveRecordingSyncChanges()
        let second = try context.fetch(FetchDescriptor<SyncChange>())
        #expect(second.count == 211)
        #expect(Set(second.map(\.recordName)) == Set(first.map(\.recordName)))
    }

    @Test func deletingParentsAlsoRecordsSurvivingObjectsWithNullifiedRelationships() throws {
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let parent = Folder(title: "Parent"), child = Folder(title: "Child", parent: parent)
        let book = Notebook(title: "Kept", folder: parent), page = NotePage(pageIndex: 0)
        let section = NotebookSection(title: "Removed section", sortIndex: 0)
        context.insert(parent); context.insert(child); context.insert(book); context.insert(page); context.insert(section)
        book.pages = [page]; book.sections = [section]; section.pages = [page]
        try context.saveRecordingSyncChanges()
        for row in try context.fetch(FetchDescriptor<SyncChange>()) { context.delete(row) }
        try context.save()
        let parentID = parent.id, sectionID = section.id
        context.delete(parent); context.delete(section)
        try context.saveRecordingSyncChanges()
        let rows = try context.fetch(FetchDescriptor<SyncChange>())
        #expect(child.parent == nil && book.folder == nil && page.section == nil)
        for id in [child.id, book.id, page.id] {
            #expect(rows.contains { $0.entityID == id && $0.operationRawValue == "upsert" })
        }
        for id in [parentID, sectionID] {
            #expect(rows.contains { $0.entityID == id && $0.operationRawValue == "delete" })
        }
    }

    @Test func installedV7StoreMigratesWithoutChangingImagesSourcesOrAssetBytes() throws {
        try withStore { url in
            let pageID = UUID(), bookID = UUID(), cardID = UUID()
            let inkURL = url.deletingLastPathComponent().appendingPathComponent("kept.drawing")
            let ink = Data([1, 4, 9, 16]); try ink.write(to: inkURL)
            do {
                // Same global seven-entity layout used by the installed app, independent
                // of the new frozen V7 migration snapshot's nested model types.
                let schema = Schema(versionedSchema: InstalledV7Schema.self)
                let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
                container.mainContext.autosaveEnabled = false
                let book = Notebook(title: "Existing", id: bookID), page = NotePage(pageIndex: 2, id: pageID)
                page.drawingFilePath = "kept.drawing"; page.pdfFilePath = "Sources/original.pdf"; page.pdfPageIndex = 4
                let deck = StudyDeck(title: "Linked", notebookID: bookID)
                let card = Flashcard(question: "Image", answer: "Answer", sourceNotebookID: bookID, sourcePageID: pageID, id: cardID)
                card.questionImagePath = "Images/question.png"; card.answerImagePath = "Images/answer.png"
                let review = ReviewRecord(rating: "easy", reviewedAt: .now, nextReviewAt: .now, intervalSeconds: 600)
                for model: any PersistentModel in [book, page, deck, card, review] { container.mainContext.insert(model) }
                book.pages = [page]; deck.cards = [card]; card.reviews = [review]
                try container.mainContext.save()
            }
            let migrated = try PersistenceController.makeContainer(storeURL: url), context = migrated.mainContext
            let book = try #require(context.fetch(FetchDescriptor<Notebook>()).first)
            let card = try #require(context.fetch(FetchDescriptor<Flashcard>()).first)
            #expect(book.id == bookID && book.pages.first?.id == pageID)
            #expect(book.pages.first?.drawingFilePath == "kept.drawing" && book.pages.first?.pdfPageIndex == 4)
            #expect(card.id == cardID && card.sourcePageID == pageID && card.sourceNotebookID == bookID)
            #expect(card.questionImagePath == "Images/question.png" && card.answerImagePath == "Images/answer.png")
            #expect(card.reviews.first?.ratingRawValue == "easy")
            #expect(try Data(contentsOf: inkURL) == ink)
            #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 0)
            book.title = "Edited after migration"; try context.saveRecordingSyncChanges()
            #expect(try context.fetchCount(FetchDescriptor<SyncChange>()) == 1)
        }
    }

    private func withStore(_ action: (URL) throws -> Void) throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try action(root.appendingPathComponent("library.store"))
    }
}

private enum InstalledV7Schema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(7, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Folder.self, Notebook.self, NotePage.self, NotebookSection.self, StudyDeck.self, Flashcard.self, ReviewRecord.self]
    }
}
