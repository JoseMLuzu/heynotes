import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct LibrarySortTests {
    @Test func repeatedLibrarySortingWorkload() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        var folders: [Folder] = []
        for index in 0..<60 {
            let parent = index % 6 == 0 ? nil : folders.last
            let folder = Folder(title: "Subject \(index)", parent: parent,
                                createdAt: Date(timeIntervalSince1970: Double(index)))
            context.insert(folder); folders.append(folder)
        }
        let books = (0..<360).map { index in
            let book = notebook("Lecture \(360 - index)", modifiedAt: Double(index + 100), in: context)
            book.folder = folders[index % folders.count]
            if index.isMultiple(of: 3) { book.pages[0].pdfFilePath = "Sources/\(index).pdf" }
            return book
        }
        try context.save()
        // Warm the relationships before measuring repeated render-time sorting.
        for order in LibrarySortOrder.allCases {
            _ = order.sortedNotebooks(books)
            _ = order.sortedFolders(folders, allFolders: folders, notebooks: books)
        }
        let start = ContinuousClock.now
        for _ in 0..<5 {
            for order in LibrarySortOrder.allCases {
                let sorted = order.sortedNotebooks(books)
                #expect(sorted.count == books.count)
                #expect(order.sortedFolders(folders, allFolders: folders, notebooks: books).count == folders.count)
            }
        }
        print("LIBRARY_SORT books=360 folders=60 passes=5 duration=\(start.duration(to: .now))")
        #expect(LibrarySortOrder.name.sortedNotebooks(books).first === books.last)
        #expect(LibrarySortOrder.recent.sortedNotebooks(books).first === books.last)
        let expectedTypes = books.filter { $0.pages[0].pdfFilePath == nil }.reversed()
            + books.filter { $0.pages[0].pdfFilePath != nil }.reversed()
        #expect(LibrarySortOrder.type.sortedNotebooks(books).map(\.id) == expectedTypes.map(\.id))
        #expect(!context.hasChanges, "Sorting must not modify persisted data.")
        withExtendedLifetime(container) {}
    }

    private func notebook(_ title: String, modifiedAt time: TimeInterval, id: UUID = UUID(), in context: ModelContext) -> Notebook {
        let notebook = Notebook(title: title, id: id, now: Date(timeIntervalSince1970: time))
        context.insert(notebook)
        let page = NotePage(pageIndex: 0)
        context.insert(page)
        notebook.pages = [page]
        return notebook
    }

    @Test func nameUsesNaturalOrderAndStableIDsForEqualTitles() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let ten = notebook("Lecture 10", modifiedAt: 3, in: context)
        let two = notebook("Lecture 2", modifiedAt: 2, in: context)
        let biology = notebook("Biology", modifiedAt: 1, in: context)
        #expect(LibrarySortOrder.name.sortedNotebooks([ten, two, biology]).map(\.id) == [biology.id, two.id, ten.id])
        let first = notebook("Same", modifiedAt: 10, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, in: context)
        let second = notebook("Same", modifiedAt: 20, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, in: context)
        #expect(LibrarySortOrder.name.sortedNotebooks([second, first]).map(\.id) == [first.id, second.id])
        withExtendedLifetime(container) {}
    }

    @Test func recentUsesModificationDateAndKeepsOriginalMetadata() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let older = notebook("A", modifiedAt: 10, in: context)
        let latest = notebook("Z", modifiedAt: 30, in: context)
        let middle = notebook("B", modifiedAt: 20, in: context)
        let original = [older, latest, middle]
        #expect(LibrarySortOrder.recent.sortedNotebooks(original).map(\.id) == [latest.id, middle.id, older.id])
        #expect(original.map(\.id) == [older.id, latest.id, middle.id])
        #expect(original.map(\.updatedAt) == [10.0, 30.0, 20.0].map(Date.init(timeIntervalSince1970:)))
        withExtendedLifetime(container) {}
    }

    @Test func typeGroupsNotebooksBeforePDFIncludingMixedPages() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let notes = notebook("Z Notes", modifiedAt: 1, in: context)
        let pdf = notebook("A Lecture", modifiedAt: 2, in: context)
        let pdfPage = NotePage(pageIndex: 1)
        pdfPage.pdfFilePath = "Notebooks/lecture.pdf"
        context.insert(pdfPage)
        pdf.pages.append(pdfPage)
        #expect(LibrarySortOrder.type.sortedNotebooks([pdf, notes]).map(\.id) == [notes.id, pdf.id])
        #expect(pdf.pages.last?.pdfFilePath == "Notebooks/lecture.pdf")
        withExtendedLifetime(container) {}
    }

    @Test func recentFoldersIncludeNestedEditsAndNewSubfolders() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let zero = Date(timeIntervalSince1970: 0)
        let biology = Folder(title: "Biology", createdAt: zero)
        let child = Folder(title: "Unit 1", parent: biology, createdAt: zero)
        let chemistry = Folder(title: "Chemistry", createdAt: zero)
        let history = Folder(title: "History", createdAt: Date(timeIntervalSince1970: 400))
        for folder in [biology, child, chemistry, history] { context.insert(folder) }
        let nested = notebook("Cells", modifiedAt: 300, in: context)
        nested.folder = child
        let direct = notebook("Atoms", modifiedAt: 200, in: context)
        direct.folder = chemistry
        let visible = [biology, chemistry, history]
        let allFolders = [biology, child, chemistry, history]
        #expect(LibrarySortOrder.recent.sortedFolders(visible, allFolders: allFolders, notebooks: [nested, direct]).map(\.id) == [history.id, biology.id, chemistry.id])
        let fresh = Folder(title: "Unit 2", parent: biology, createdAt: Date(timeIntervalSince1970: 500))
        context.insert(fresh)
        #expect(LibrarySortOrder.recent.sortedFolders(visible, allFolders: allFolders + [fresh], notebooks: [nested, direct]).map(\.id) == [biology.id, history.id, chemistry.id])
        #expect(LibrarySortOrder.type.sortedFolders(visible.reversed(), allFolders: allFolders, notebooks: []).map(\.id) == [biology.id, chemistry.id, history.id])
        withExtendedLifetime(container) {}
    }

    @Test func sortingReflectsMovesEditsAndPDFChangesWithoutRetainedKeys() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let zero = Date(timeIntervalSince1970: 0)
        let first = Folder(title: "Subject 2", createdAt: zero)
        let second = Folder(title: "Subject 10", createdAt: zero)
        let child = Folder(title: "Nested", parent: first, createdAt: zero)
        for folder in [first, second, child] { context.insert(folder) }
        let older = notebook("Lecture 2", modifiedAt: 10, in: context)
        let newer = notebook("Lecture 10", modifiedAt: 20, in: context)
        older.folder = first; newer.folder = child
        let visible = [second, first]
        // Ancestors absent from allFolders must still inherit the nested edit.
        #expect(LibrarySortOrder.recent.sortedFolders(visible, allFolders: [child], notebooks: [older, newer]).first === first)
        child.parent = second
        #expect(LibrarySortOrder.recent.sortedFolders(visible, allFolders: [child], notebooks: [older, newer]).first === second)
        newer.updatedAt = older.updatedAt
        #expect(LibrarySortOrder.recent.sortedNotebooks([newer, older]).first === older)
        older.title = "Lecture 30"
        #expect(LibrarySortOrder.recent.sortedNotebooks([newer, older]).first === newer)
        newer.pages[0].pdfFilePath = "Sources/lecture.pdf"
        #expect(LibrarySortOrder.type.sortedNotebooks([newer, older]).first === older)
        newer.pages[0].pdfFilePath = nil
        #expect(LibrarySortOrder.type.sortedNotebooks([newer, older]).first === newer)
        first.createdAt = Date(timeIntervalSince1970: 30)
        #expect(LibrarySortOrder.recent.sortedFolders(visible, allFolders: [first, second, child], notebooks: [older, newer]).first === first)
        withExtendedLifetime(container) {}
    }
}
