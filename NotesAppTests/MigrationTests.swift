import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct MigrationTests {
    @Test func phaseThreePDFStoreMigratesToHierarchyWithoutChangingIDsOrPaths() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        let notebookID = UUID(), pageID = UUID()
        do {
            let schema = Schema(versionedSchema: NotesSchemaV2.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let folder = NotesSchemaV2.Folder(title: "Biology")
            let notebook = NotesSchemaV2.Notebook(title: "PDF notes", folder: folder, id: notebookID)
            let page = NotesSchemaV2.NotePage(pageIndex: 0, id: pageID)
            page.drawingFilePath = "ink/kept.drawing"; page.pdfFilePath = "Sources/kept.pdf"
            page.pdfPageIndex = 4; page.pageWidth = 300; page.pageHeight = 200
            container.mainContext.insert(folder); container.mainContext.insert(notebook); container.mainContext.insert(page)
            notebook.pages = [page]; notebook.isFavorite = true
            try container.mainContext.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url)
        let notebook = try #require(migrated.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        #expect(notebook.id == notebookID)
        #expect(notebook.folder?.title == "Biology")
        #expect(notebook.folder?.parent == nil)
        #expect(notebook.folder?.isFavorite == false)
        #expect(!notebook.isInTrash)
        #expect(notebook.isFavorite)
        let page = try #require(notebook.pages.first)
        #expect(page.id == pageID)
        #expect(page.drawingFilePath == "ink/kept.drawing")
        #expect(page.pdfFilePath == "Sources/kept.pdf")
        #expect(page.pdfPageIndex == 4)
        #expect(page.logicalSize.width == 300)
    }

    @Test func unversionedPhaseTwoStoreMigratesWithoutLosingInkReferences() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        let id = UUID(), pageID = UUID()
        do {
            // Mimics the previously shipped unversioned schema, not a fresh V2 store.
            let schema = Schema(NotesSchemaV1.models)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let folder = NotesSchemaV1.Folder(title: "Semester")
            let notebook = NotesSchemaV1.Notebook(title: "Existing notes", coverColor: .rose, folder: folder, id: id)
            let page = NotesSchemaV1.NotePage(pageIndex: 0, paperTemplate: .grid, id: pageID)
            page.drawingFilePath = "Notebooks/old/Pages/ink.drawing"
            container.mainContext.insert(folder); container.mainContext.insert(notebook); container.mainContext.insert(page)
            notebook.pages = [page]; notebook.isFavorite = true
            try container.mainContext.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url)
        let notebook = try #require(migrated.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        #expect(notebook.id == id)
        #expect(notebook.title == "Existing notes")
        #expect(notebook.folder?.title == "Semester")
        #expect(notebook.isFavorite)
        #expect(notebook.pages.first?.id == pageID)
        #expect(notebook.pages.first?.drawingFilePath == "Notebooks/old/Pages/ink.drawing")
        #expect(notebook.pages.first?.paperTemplate == .grid)
        #expect(notebook.pages.first?.pdfFilePath == nil)
        #expect(notebook.pages.first?.logicalSize.width == 768)
        #expect(notebook.pages.first?.logicalSize.height == 1086)
    }
}
