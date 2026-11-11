import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct StudentOrganizationTests {
    @Test func v3MigrationPreservesExistingNotebookAndBinaryReferences() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), inkURL = root.appendingPathComponent("kept.drawing")
        let bytes = Data("original editable ink".utf8); try bytes.write(to: inkURL)
        let notebookID = UUID(), pageID = UUID()
        do {
            let schema = Schema(versionedSchema: NotesSchemaV3.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let legacy = try ModelContainer(for: schema, configurations: [config])
            let folder = NotesSchemaV3.Folder(title: "University")
            let notebook = NotesSchemaV3.Notebook(title: "Existing", folder: folder, id: notebookID)
            notebook.coverColorRawValue = "textures.moonlight"
            let page = NotesSchemaV3.NotePage(pageIndex: 0, paperTemplate: .cornell, id: pageID)
            page.drawingFilePath = "kept.drawing"; page.pdfFilePath = "lecture.pdf"; page.pdfPageIndex = 2
            page.pageWidth = 600; page.pageHeight = 800
            legacy.mainContext.insert(folder); legacy.mainContext.insert(notebook); legacy.mainContext.insert(page)
            notebook.pages = [page]; try legacy.mainContext.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url)
        let notebook = try #require(migrated.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        let page = try #require(notebook.pages.first)
        #expect(notebook.id == notebookID && page.id == pageID)
        #expect(notebook.coverStyle == .moonlight && notebook.folder?.title == "University")
        #expect(page.paperTemplate == .cornell && page.drawingFilePath == "kept.drawing")
        #expect(page.pdfFilePath == "lecture.pdf" && page.pdfPageIndex == 2)
        #expect(page.logicalSize == CGSize(width: 600, height: 800))
        #expect(page.bookmarkTitle == nil && page.section == nil && page.objectsData == nil && notebook.sections.isEmpty)
        #expect(try Data(contentsOf: inkURL) == bytes)
    }

    @Test func sectionsBookmarksAndContentReopenAndDuplicateIndependently() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), storage = DrawingStorage(root: root.appendingPathComponent("files"))
        let container = try PersistenceController.makeContainer(storeURL: url)
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        #expect(model.createNotebook(title: "Biology", color: .sage, template: .ruled, folder: nil))
        let notebook = try #require(model.notebooks.first), first = try #require(notebook.pages.first)
        let id = first.id
        let a = NotebookSection(title: "Unit 1", sortIndex: 0), b = NotebookSection(title: "Unit 2", sortIndex: 1)
        container.mainContext.insert(a); container.mainContext.insert(b); notebook.sections = [a, b]
        let second = NotePage(pageIndex: 1); container.mainContext.insert(second); notebook.pages.append(second)
        #expect(NotebookOrganization.assign(second, to: b, in: notebook))
        #expect(NotebookOrganization.assign(first, to: a, in: notebook))
        let alien = Notebook(title: "Other"), wrong = NotebookSection(title: "Wrong", sortIndex: 0)
        container.mainContext.insert(alien); container.mainContext.insert(wrong); alien.sections = [wrong]
        #expect(!NotebookOrganization.assign(first, to: wrong, in: notebook))
        first.bookmarkTitle = "Exam formulas"; first.pdfRightMargin = 240
        var item = PageElement(kind: .image, rect: CGRect(x: 40, y: 40, width: 100, height: 80))
        item.imagePath = "Notebooks/source/Images/picture.jpg"
        let imageBytes = Data("copied image asset".utf8); try await storage.write(imageBytes, to: item.imagePath!)
        first.objectsData = try PageElementsCodec.encode([item])
        try container.mainContext.save()
        await model.duplicate(notebook)
        #expect(model.errorMessage == nil)
        let copy = try #require(model.notebooks.first { $0.id != notebook.id })
        #expect(copy.sections.count == 2 && copy.sections.allSatisfy { $0.id != a.id && $0.id != b.id })
        let copiedPage = try #require(copy.orderedPages.first)
        #expect(copiedPage.bookmarkTitle == first.bookmarkTitle && copiedPage.pdfRightMargin == 240)
        #expect(copiedPage.section?.title == "Unit 1")
        let copiedItem = try #require(PageElementsCodec.decode(copiedPage.objectsData).first)
        #expect(copiedItem.id != item.id && copiedItem.imagePath != item.imagePath)
        #expect(try await storage.read(copiedItem.imagePath!) == imageBytes)
        a.sortIndex = 1; b.sortIndex = 0; NotebookOrganization.normalize(notebook)
        #expect(notebook.orderedPages.first?.id == second.id)
        #expect(first.id == id)
        container.mainContext.delete(a); NotebookOrganization.normalize(notebook)
        try container.mainContext.save()
        #expect(first.section == nil && notebook.pages.count == 2)
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let pages = try reopened.mainContext.fetch(FetchDescriptor<NotePage>())
        #expect(pages.first { $0.id == id }?.bookmarkTitle == "Exam formulas")
    }
}
