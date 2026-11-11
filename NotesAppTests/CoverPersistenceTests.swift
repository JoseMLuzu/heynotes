import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct CoverPersistenceTests {
    @Test func subjectCoversReopenAndCopyWithoutChangingInkOrLegacyAtlasIndices() async throws {
        #expect(CoverStyle.allCases.count == 57)
        #expect(CoverStyle.ivoryLinen.artworkIndex == 0)
        #expect(CoverStyle.moonlight.artworkIndex == 39)
        #expect(CoverStyle.mathematicsCover.artworkIndex == nil)
        #expect(CoverStyle.mathematicsCover.subject == .mathematics)
        #expect(CoverStyle.mathematicsCover.collection == .subjects)
        #expect(NotebookSubject.mathematics.searchTerms.localizedStandardContains("matematicas"))
        #expect(Set(CoverStyle.allCases.map(\.rawValue)).count == 57)
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("subjects.store"), storage = DrawingStorage(root: root)
        var notebookID: UUID?, pageID: UUID?
        let bytes = Data("cover-independent editable notes".utf8)
        do {
            let container = try PersistenceController.makeContainer(storeURL: store)
            let model = LibraryViewModel(context: container.mainContext, storage: storage)
            #expect(model.createNotebook(title: "Mathematics", color: .blue, template: .grid, folder: nil, cover: .mathematicsCover))
            let notebook = try #require(model.notebooks.first), page = try #require(notebook.pages.first)
            notebookID = notebook.id; pageID = page.id
            let path = DrawingStorage.path(notebook: notebook.id, page: page.id)
            try await storage.write(bytes, to: path); page.drawingFilePath = path
            try container.mainContext.save()
            #expect(model.changeCover(notebook, to: .historyCover))
            #expect(try await storage.read(path) == bytes)
            await model.duplicate(notebook)
            let copy = try #require(model.notebooks.first { $0.id != notebook.id })
            #expect(copy.coverColorRawValue == "subjects.history")
            #expect(copy.pages.first?.id != pageID)
            #expect(try await storage.read(try #require(copy.pages.first?.drawingFilePath)) == bytes)
        }
        let reopened = try PersistenceController.makeContainer(storeURL: store)
        let notebook = try #require(reopened.mainContext.fetch(FetchDescriptor<Notebook>()).first { $0.id == notebookID })
        #expect(notebook.coverStyle == .historyCover && notebook.coverColor == .sand)
        #expect(notebook.pages.first?.id == pageID)
    }

    @Test func coverChangeReopensAndDuplicatesWithoutTouchingPageFiles() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("library.store")
        let storage = DrawingStorage(root: root.appendingPathComponent("drawings"))
        var notebookID: UUID?, pageID: UUID?, drawingPath: String?
        let bytes = Data("editable ink stays independent of covers".utf8)
        do {
            let container = try PersistenceController.makeContainer(storeURL: store)
            let model = LibraryViewModel(context: container.mainContext, storage: storage)
            #expect(model.createNotebook(title: "Botany", color: .sage, template: .cornell, folder: nil, cover: .oliveBranches))
            let notebook = try #require(model.notebooks.first), page = try #require(notebook.pages.first)
            notebookID = notebook.id; pageID = page.id
            let path = DrawingStorage.path(notebook: notebook.id, page: page.id)
            drawingPath = path
            try await storage.write(bytes, to: path)
            page.drawingFilePath = path
            page.pdfFilePath = "Notebooks/source.pdf"; page.pdfPageIndex = 3
            page.pageWidth = 600; page.pageHeight = 800
            try container.mainContext.save()
            #expect(model.changeCover(notebook, to: .moonlight))
            #expect(page.id == pageID && page.drawingFilePath == path)
            #expect(page.pdfFilePath == "Notebooks/source.pdf" && page.pdfPageIndex == 3)
            #expect(page.pageWidth == 600 && page.pageHeight == 800)
            #expect(try await storage.read(path) == bytes)
            let editedAt = notebook.updatedAt
            #expect(model.changeCover(notebook, to: .moonlight))
            #expect(notebook.updatedAt == editedAt)
            // The duplication fixture uses saved ink only; PDF copy behavior has separate tests.
            page.pdfFilePath = nil; page.pdfPageIndex = nil
            try container.mainContext.save()
            await model.duplicate(notebook)
            let copy = try #require(model.notebooks.first { $0.id != notebook.id })
            #expect(copy.coverStyle == .moonlight)
            #expect(copy.pages.first?.id != page.id)
            let copyPath = try #require(copy.pages.first?.drawingFilePath)
            #expect(copyPath != path)
            #expect(try await storage.read(copyPath) == bytes)
            model.delete(notebook)
            #expect(!model.changeCover(notebook, to: .tulips))
            model.restore(notebook)
        }
        let reopened = try PersistenceController.makeContainer(storeURL: store)
        let notebook = try #require(reopened.mainContext.fetch(FetchDescriptor<Notebook>()).first { $0.id == notebookID })
        #expect(notebook.coverStyle == .moonlight && notebook.coverColor == .graphite)
        #expect(notebook.pages.first?.id == pageID)
        #expect(notebook.pages.first?.drawingFilePath == drawingPath)
    }
}
