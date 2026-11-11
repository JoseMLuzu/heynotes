import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

struct DrawingStorageTests {
    @Test func atomicReplacementAndBackupRecovery() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let path = DrawingStorage.path(notebook: UUID(), page: UUID())
        let first = Data([1, 2, 3]), second = Data([4, 5, 6])
        try await storage.write(first, to: path)
        try await storage.write(second, to: path)
        #expect(try await storage.read(path) == second)
        #expect(try await storage.read(path + ".backup") == first)
        #expect(try await storage.restoreBackup(path) == first)
        #expect(try await storage.read(path) == first)
        let siblings = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(path).deletingLastPathComponent(), includingPropertiesForKeys: nil)
        #expect(siblings.contains { $0.path.contains("damaged-") })
    }

    @Test func rejectsTraversalAndPreservesDataOnWriteFailure() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        await #expect(throws: (any Error).self) { try await storage.write(Data(), to: "../escape") }
        await #expect(throws: (any Error).self) { try await storage.read("/etc/passwd") }
        await #expect(throws: (any Error).self) { try await storage.read("missing.drawing") }
        try Data([8]).write(to: root.appendingPathComponent("blocked"))
        await #expect(throws: (any Error).self) { try await storage.write(Data([9]), to: "blocked/page.drawing") }
        #expect(try Data(contentsOf: root.appendingPathComponent("blocked")) == Data([8]))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: URL.temporaryDirectory)
        await #expect(throws: (any Error).self) { try await storage.write(Data(), to: "link/escape") }
    }
}

@MainActor struct PageOrderTests {
    @Test func movesAndDeletionRemainContiguousAfterReopening() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Order")
        container.mainContext.insert(notebook)
        for i in 0..<4 {
            let page = NotePage(pageIndex: i)
            container.mainContext.insert(page); notebook.pages.append(page)
        }
        let first = notebook.orderedPages[0]
        PageOrdering.move(first, in: notebook, offset: 2)
        #expect(notebook.orderedPages[2].id == first.id)
        let deleted = notebook.orderedPages[1]
        notebook.pages.removeAll { $0.id == deleted.id }
        container.mainContext.delete(deleted)
        PageOrdering.normalize(notebook.orderedPages)
        try container.mainContext.save()
        let context = ModelContext(container)
        let reloaded = try #require(context.fetch(FetchDescriptor<Notebook>()).first)
        #expect(reloaded.orderedPages.map(\.pageIndex) == [0, 1, 2])
        #expect(reloaded.orderedPages[1].id == first.id)
    }

    @Test func notebookCopyUsesIndependentDrawingFiles() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        #expect(model.createNotebook(title: "Ink", color: .sage, template: .grid, folder: nil))
        let original = try #require(model.notebooks.first)
        let page = try #require(original.pages.first)
        let path = DrawingStorage.path(notebook: original.id, page: page.id)
        try await storage.write(Data([1, 2, 3]), to: path)
        page.drawingFilePath = path
        try container.mainContext.save()
        await model.duplicate(original)
        let copy = try #require(model.notebooks.first { $0.id != original.id })
        let copyPath = try #require(copy.pages.first?.drawingFilePath)
        #expect(copyPath != path)
        try await storage.write(Data([9]), to: copyPath)
        #expect(try await storage.read(path) == Data([1, 2, 3]))
        model.delete(original)
        #expect(try await storage.read(path) == Data([1, 2, 3]))
    }
}
