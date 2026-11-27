import Foundation
import SwiftData
import CoreData
import Testing
@testable import NotesAppCore

@MainActor struct PageRecoveryTests {
    @Test func removedPagesSurviveReopenAndRestoreStableOrderSourcesAndJournal() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), bookID = UUID(), pageID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let bytes = Data([1, 2, 3]); try bytes.write(to: root.appendingPathComponent("ink.drawing"))
        do {
            let container = try PersistenceController.makeContainer(storeURL: url), context = container.mainContext
            let book = Notebook(title: "Biology", id: bookID)
            let section = NotebookSection(title: "Cells", sortIndex: 0)
            let first = NotePage(pageIndex: 0), removed = NotePage(pageIndex: 1, id: pageID), last = NotePage(pageIndex: 2)
            let card = Flashcard(question: "Q", answer: "A", sourceNotebookID: bookID, sourcePageID: pageID)
            for value: any PersistentModel in [book, section, first, removed, last, card] { context.insert(value) }
            book.sections = [section]; book.pages = [first, removed, last]; section.pages = [first, removed, last]
            removed.drawingFilePath = "ink.drawing"; removed.bookmarkTitle = "Exam"
            removed.pdfFilePath = "Source.pdf"; removed.pdfPageIndex = 3; removed.pdfRightMargin = 120
            removed.objectsData = try PageElementsCodec.encode([PageElement(kind: .text, rect: CGRect(x: 10, y: 20, width: 100, height: 40))])
            try context.saveRecordingSyncChanges()
            #expect(PageRecovery.remove(removed, from: book, at: date))
            try context.saveRecordingSyncChanges()
            #expect(book.activePageCount == 2 && book.pages.count == 3)
            #expect(book.orderedPages.map(\.id) == [first.id, last.id])
            #expect(book.orderedPages.map(\.pageIndex) == [0, 1])
            #expect(card.sourcePageID == pageID)
            #expect(!PageRecovery.remove(removed, from: book))
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url), context = reopened.mainContext
        let book = try #require(context.fetch(FetchDescriptor<Notebook>()).first), page = try #require(book.removedPages.first)
        #expect(page.id == pageID && page.trashedAt == date && page.pageIndex == 1)
        #expect(page.section?.title == "Cells" && page.bookmarkTitle == "Exam")
        #expect(page.pdfFilePath == "Source.pdf" && page.pdfPageIndex == 3 && page.pdfRightMargin == 120)
        #expect(try PageElementsCodec.decode(page.objectsData).count == 1)
        let row = try #require(context.fetch(FetchDescriptor<SyncChange>()).first { $0.entityID == pageID })
        #expect(row.operationRawValue == "upsert")
        let revision = row.revision
        #expect(PageRecovery.restore(page, in: book)); try context.saveRecordingSyncChanges()
        #expect(book.orderedPages[1].id == pageID && book.activePageCount == 3 && book.removedPages.isEmpty)
        #expect(row.revision != revision && row.operationRawValue == "upsert")
        #expect(try context.fetch(FetchDescriptor<Flashcard>()).first?.sourcePageID == pageID)
        #expect(page.drawingFilePath == "ink.drawing")
        #expect(try Data(contentsOf: root.appendingPathComponent("ink.drawing")) == bytes)
        #expect(!PageRecovery.restore(page, in: book))
    }

    @Test func lastPageWrongNotebookAndRollbackAreSafe() throws {
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let book = Notebook(title: "A"), other = Notebook(title: "B"), a = NotePage(pageIndex: 0), b = NotePage(pageIndex: 1)
        for value: any PersistentModel in [book, other, a, b] { context.insert(value) }
        book.pages = [a, b]; try context.saveRecordingSyncChanges()
        #expect(!PageRecovery.remove(a, from: other))
        #expect(PageRecovery.remove(a, from: book)); try context.saveRecordingSyncChanges()
        #expect(!PageRecovery.remove(b, from: book))
        let index = b.pageIndex
        #expect(PageRecovery.restore(a, in: book)); try SyncChangeJournal.recordPendingChanges(in: context)
        context.rollback() // A failed save must not commit recovery or its journal independently.
        #expect(a.trashedAt != nil && b.pageIndex == index && book.activePageCount == 1)
        #expect(!PageRecovery.restore(a, in: other))
        #expect(PageRecovery.restore(a, in: book)); try context.saveRecordingSyncChanges()
        #expect(book.orderedPages.map(\.pageIndex) == [0, 1])
    }

    @Test func frozenV8DiskMigrationRetainsContentAndPendingRevisions() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), pageID = UUID(), revision = UUID()
        let ink = Data([6, 7, 8]), file = root.appendingPathComponent("kept.drawing"); try ink.write(to: file)
        do {
            let schema = Schema(versionedSchema: NotesSchemaV8.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let book = NotesSchemaV8.Notebook(title: "V8")
            let page = NotesSchemaV8.NotePage(pageIndex: 0, id: pageID)
            let section = NotesSchemaV8.NotebookSection(title: "Unit", sortIndex: 0)
            let card = NotesSchemaV8.Flashcard(question: "Q", answer: "A", sourceNotebookID: book.id, sourcePageID: pageID)
            let change = NotesSchemaV8.SyncChange(identity: .init(kind: .page, id: pageID), operation: .upsert)
            change.revision = revision
            page.drawingFilePath = "kept.drawing"; page.pdfFilePath = "Source.pdf"; page.pdfPageIndex = 2; page.bookmarkTitle = "Kept"
            for value: any PersistentModel in [book, page, section, card, change] { old.mainContext.insert(value) }
            book.pages = [page]; book.sections = [section]; page.section = section
            try old.mainContext.save()
        }
        // Captured from the unmodified global V8 models at commit 743c556, not derived
        // from this frozen snapshot. Detect accidental changes to the old model layout.
        let originalHashes: [String: String] = [
            "Flashcard": "yZa84xIwOkR543nseuxyXX2dvrkG/L+ZWlY8hbdbK9I=",
            "Folder": "b/ml9r8w3QzFsVGjFVmjRcG4UTGc6DIT8qaNT38JNk0=",
            "NotePage": "txEW15SUFRnYz1FXfDXkWyAOKQnUnh/3xSBWS6jiL7I=",
            "Notebook": "iUohA0Y+Z4nWnMISRxSBmjiX7RjakO5BJZU+uKGtzmY=",
            "NotebookSection": "1yUCjy3CA1OuYrtmpFv5X2SOmvoDHj+zmmQQaA0qI0Q=",
            "ReviewRecord": "is97ndUxnEtWFPZ/FpIu35i0BJtI1grWfFr+ask4F1s=",
            "StudyDeck": "FUxoo7fBPyPuK4cGsyhYJDTZGuktrmav3qoR8roOaxI=",
            "SyncChange": "FTi4whFT4NAchlOY6vSWhXDV9OQtwmEFESa2NE1POxA="
        ]
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        #expect(hashes.mapValues { $0.base64EncodedString() } == originalHashes)
        let migrated = try PersistenceController.makeContainer(storeURL: url), context = migrated.mainContext
        let page = try #require(context.fetch(FetchDescriptor<NotePage>()).first)
        #expect(page.id == pageID && page.trashedAt == nil && page.pageIndex == 0)
        #expect(page.drawingFilePath == "kept.drawing" && page.pdfPageIndex == 2 && page.bookmarkTitle == "Kept")
        #expect(page.section?.title == "Unit" && page.notebook?.activePageCount == 1)
        #expect(try context.fetch(FetchDescriptor<SyncChange>()).first?.revision == revision)
        #expect(try context.fetch(FetchDescriptor<Flashcard>()).first?.sourcePageID == pageID)
        #expect(try Data(contentsOf: file) == ink)
    }

    private func directory() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
