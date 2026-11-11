import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor
struct LibraryTests {
    @Test func notebookSurvivesStoreReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.store")
        var id: UUID?
        do {
            let container = try PersistenceController.makeContainer(storeURL: url)
            let model = LibraryViewModel(context: container.mainContext)
            #expect(model.createNotebook(title: "  Biology  ", color: .sage, template: .ruled, folder: nil))
            id = try #require(model.notebooks.first).id
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let model = LibraryViewModel(context: reopened.mainContext)
        let notebook = try #require(model.notebooks.first)
        #expect(notebook.id == id)
        #expect(notebook.title == "Biology")
        #expect(notebook.pages.count == 1)
        #expect(notebook.pages.first?.paperTemplate == .ruled)
        #expect(notebook.pages.first?.notebook?.id == notebook.id)
    }

    @Test func trashPreservesNotebookPagesAndFolderRelationships() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext)
        #expect(model.createFolder(title: "Science"))
        let folder = try #require(model.folders.first)
        #expect(model.createNotebook(title: "Biology", color: .blue, template: .grid, folder: folder))
        let notebook = try #require(model.notebooks.first)
        model.delete(folder)
        #expect(model.folders.isEmpty)
        #expect(model.notebooks.isEmpty)
        #expect(model.trashedFolders.first?.id == folder.id)
        model.restore(folder)
        #expect(model.notebooks.first?.folder?.id == folder.id)
        model.delete(notebook)
        #expect(model.notebooks.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<NotePage>()) == 1)
        model.restore(notebook)
        #expect(model.notebooks.first?.id == notebook.id)
    }

    @Test func duplicationHasIndependentIdentifiersAndStablePageOrder() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext)
        #expect(model.createNotebook(title: "Chemistry", color: .rose, template: .blank, folder: nil))
        let original = try #require(model.notebooks.first)
        let page = NotePage(pageIndex: 1, paperTemplate: .grid)
        container.mainContext.insert(page)
        original.pages.insert(page, at: 0)
        try container.mainContext.save()
        await model.duplicate(original)
        let copy = try #require(model.notebooks.first { $0.id != original.id })
        #expect(copy.title == "Chemistry Copy")
        #expect(copy.orderedPages.map(\.pageIndex) == [0, 1])
        #expect(copy.orderedPages.map(\.paperTemplate) == [.blank, .grid])
        #expect(Set(copy.pages.map(\.id)).isDisjoint(with: original.pages.map(\.id)))
        #expect(copy.pages.allSatisfy { $0.notebook?.id == copy.id })
    }

    @Test func validationAndBinaryGuardLeaveOriginalUntouched() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext)
        #expect(!model.createNotebook(title: " \n ", color: .sage, template: .blank, folder: nil))
        #expect(model.notebooks.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(model.createNotebook(title: "Physics", color: .graphite, template: .blank, folder: nil))
        let notebook = try #require(model.notebooks.first)
        #expect(!model.rename(notebook, title: " "))
        #expect(notebook.title == "Physics")
        notebook.pages.first?.drawingFilePath = "Drawings/test.drawing"
        try container.mainContext.save()
        await model.duplicate(notebook)
        #expect(model.notebooks.count == 1)
        model.delete(notebook)
        #expect(model.notebooks.isEmpty)
    }

    @Test func favoritesAndFolderMovesPersist() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext)
        #expect(model.createNotebook(title: "Math", color: .sand, template: .blank, folder: nil))
        #expect(model.createFolder(title: "Semester One"))
        let notebook = try #require(model.notebooks.first)
        let folder = try #require(model.folders.first)
        model.toggleFavorite(notebook)
        model.move(notebook, to: folder)
        let freshContext = ModelContext(container)
        let saved = try #require(freshContext.fetch(FetchDescriptor<Notebook>()).first)
        #expect(saved.isFavorite)
        #expect(saved.folder?.id == folder.id)
        #expect(folder.notebooks.contains { $0.id == notebook.id })
    }
}
