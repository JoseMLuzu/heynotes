import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct FolderColorTests {
    @Test func frozenV4MigratesColorsWithoutChangingHierarchyPagesOrFiles() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), ids = (UUID(), UUID(), UUID(), UUID(), UUID())
        let ink = Data("unchanged ink".utf8); try ink.write(to: root.appendingPathComponent("kept.drawing"))
        do {
            let schema = Schema(versionedSchema: NotesSchemaV4.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let parent = NotesSchemaV4.Folder(title: "University", id: ids.0)
            let child = NotesSchemaV4.Folder(title: "Biology", parent: parent, id: ids.1)
            let notebook = NotesSchemaV4.Notebook(title: "Preserved", folder: child, id: ids.2)
            let page = NotesSchemaV4.NotePage(pageIndex: 0, paperTemplate: .cornell, id: ids.3)
            let section = NotesSchemaV4.NotebookSection(title: "Unit 1", sortIndex: 0, id: ids.4)
            child.isFavorite = true; notebook.coverColorRawValue = "subjects.biology"
            page.drawingFilePath = "kept.drawing"; page.pdfFilePath = "lecture.pdf"; page.pdfPageIndex = 2
            page.bookmarkTitle = "Exam"; page.pdfRightMargin = 240; page.objectsData = try PageElementsCodec.encode([])
            old.mainContext.insert(parent); old.mainContext.insert(child); old.mainContext.insert(notebook)
            old.mainContext.insert(page); old.mainContext.insert(section)
            notebook.pages = [page]; notebook.sections = [section]; page.section = section
            try old.mainContext.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url)
        let folder = try #require(migrated.mainContext.fetch(FetchDescriptor<Folder>()).first { $0.id == ids.1 })
        #expect(folder.color == .sage && folder.colorRawValue == nil && folder.isFavorite)
        #expect(folder.parent?.id == ids.0)
        let notebook = try #require(folder.notebooks.first), page = try #require(notebook.pages.first)
        #expect(notebook.id == ids.2 && page.id == ids.3 && page.section?.id == ids.4)
        #expect(page.drawingFilePath == "kept.drawing" && page.pdfFilePath == "lecture.pdf" && page.pdfPageIndex == 2)
        #expect(page.bookmarkTitle == "Exam" && page.pdfRightMargin == 240 && page.paperTemplate == .cornell)
        #expect(try Data(contentsOf: root.appendingPathComponent("kept.drawing")) == ink)
        let updatedAt = notebook.updatedAt
        let model = LibraryViewModel(context: migrated.mainContext)
        #expect(model.changeColor(folder, to: .lavender))
        model.delete(folder); model.restore(folder)
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<Folder>()).first { $0.id == ids.1 })
        #expect(saved.color == .lavender && saved.parent?.id == ids.0 && !saved.isInTrash)
        #expect(saved.notebooks.first?.id == ids.2 && saved.notebooks.first?.updatedAt == updatedAt)
    }

    @Test func unknownFolderColorFallsBackWithoutDiscardingMetadata() throws {
        let folder = Folder(title: "Future color")
        folder.colorRawValue = "future-color"
        #expect(folder.color == .sage && folder.colorRawValue == "future-color")
        folder.color = .teal
        #expect(folder.colorRawValue == "teal" && folder.color == .teal)
    }
}
