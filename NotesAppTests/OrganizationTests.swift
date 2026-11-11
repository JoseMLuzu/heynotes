import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct OrganizationTests {
    @Test func nestedFoldersPreventCyclesAndMovesKeepDocumentIdentity() async throws {
        let rootURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storage = DrawingStorage(root: rootURL)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        #expect(model.createFolder(title: "University"))
        let root = try #require(model.folders.first)
        #expect(model.createFolder(title: "Biology", parent: root))
        let biology = try #require(model.folders.first { $0.title == "Biology" })
        #expect(model.createFolder(title: "Cells", parent: biology))
        let cells = try #require(model.folders.first { $0.title == "Cells" })
        #expect(cells.pathTitle == "University / Biology / Cells")
        #expect(root.children.contains { $0.id == biology.id })
        #expect(!model.move(root, to: cells))
        #expect(!model.move(biology, to: biology))
        #expect(root.parent == nil)
        #expect(!model.validParents(for: root).contains { $0.id == cells.id })
        #expect(model.createNotebook(title: "Lecture", color: .blue, template: .grid, folder: cells))
        let notebook = try #require(model.notebooks.first), page = try #require(notebook.pages.first)
        let id = page.id
        page.drawingFilePath = DrawingStorage.path(notebook: notebook.id, page: page.id)
        page.pdfFilePath = "Sources/kept.pdf"; page.pdfPageIndex = 3
        try await storage.write(Data([1, 2, 3]), to: page.drawingFilePath!)
        try container.mainContext.save()
        let drawingPath = page.drawingFilePath
        model.move(notebook, to: root)
        #expect(notebook.folder?.id == root.id)
        #expect(page.id == id)
        #expect(page.drawingFilePath == drawingPath)
        #expect(page.pdfFilePath == "Sources/kept.pdf")
        #expect(try await storage.read(drawingPath!) == Data([1, 2, 3]))
        model.move(notebook, to: nil)
        #expect(notebook.folder == nil) // Inbox is virtual: no extra notebook or file.
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Notebook>()) == 1)
    }

    @Test func folderTrashRestoreKeepsHierarchyAndSeparatelyTrashedItems() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext)
        #expect(model.createFolder(title: "Root"))
        let root = try #require(model.folders.first)
        #expect(model.createFolder(title: "Child", parent: root))
        let child = try #require(model.folders.first { $0.parent != nil })
        model.toggleFavorite(child)
        #expect(model.createNotebook(title: "Keep", color: .sage, template: .blank, folder: child))
        #expect(model.createNotebook(title: "Previously removed", color: .rose, template: .blank, folder: child))
        let keep = try #require(model.notebooks.first { $0.title == "Keep" })
        let removed = try #require(model.notebooks.first { $0.title != "Keep" })
        let pageID = try #require(keep.pages.first).id
        model.delete(removed)
        #expect(model.documents(inSubtreeOf: root).count == 1)
        model.delete(root)
        #expect(model.folders.isEmpty)
        #expect(model.notebooks.isEmpty)
        #expect(model.trashedFolders.count == 1)
        #expect(model.trashedNotebooks.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<NotePage>()) == 2)
        model.restore(root)
        #expect(child.parent?.id == root.id)
        #expect(child.isFavorite)
        #expect(model.notebooks.map(\.id) == [keep.id])
        #expect(model.trashedNotebooks.map(\.id) == [removed.id])
        #expect(keep.pages.first?.id == pageID)
        model.restore(removed)
        #expect(model.notebooks.count == 2)
        #expect(model.trashedFolders.isEmpty)
        #expect(model.trashedNotebooks.isEmpty)
    }

    @Test func hierarchyFavoritesAndTrashSurviveStoreReopening() throws {
        let rootURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let url = rootURL.appendingPathComponent("library.store")
        do {
            let container = try PersistenceController.makeContainer(storeURL: url)
            let model = LibraryViewModel(context: container.mainContext)
            #expect(model.createFolder(title: "Root"))
            let root = try #require(model.folders.first)
            #expect(model.createFolder(title: "Child", parent: root))
            let child = try #require(model.folders.first { $0.parent != nil })
            model.toggleFavorite(child)
            #expect(model.createNotebook(title: "Lecture", color: .sage, template: .ruled, folder: child))
            model.delete(root)
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let model = LibraryViewModel(context: reopened.mainContext)
        #expect(model.notebooks.isEmpty)
        let root = try #require(model.trashedFolders.first)
        model.restore(root)
        #expect(model.notebooks.first?.folder?.pathTitle == "Root / Child")
        #expect(model.folders.contains { $0.title == "Child" && $0.isFavorite })
    }
}
