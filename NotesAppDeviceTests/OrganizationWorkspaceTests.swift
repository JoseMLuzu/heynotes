import XCTest
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class OrganizationWorkspaceTests: XCTestCase {
    func testFolderTrashClosesAllAffectedTabsAfterSavingAndCanRestore() async throws {
        let suite = "OrganizationTabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let rootURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: rootURL) }
        let storage = DrawingStorage(root: rootURL)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        XCTAssertTrue(model.createFolder(title: "University"))
        let folder = try XCTUnwrap(model.folders.first)
        XCTAssertTrue(model.createFolder(title: "Biology", parent: folder))
        let child = try XCTUnwrap(model.folders.first { $0.parent != nil })
        XCTAssertTrue(model.createNotebook(title: "A", color: .sage, template: .blank, folder: child))
        XCTAssertTrue(model.createNotebook(title: "B", color: .sage, template: .blank, folder: folder))
        XCTAssertTrue(model.createNotebook(title: "Outside", color: .blue, template: .blank, folder: nil))
        let a = try XCTUnwrap(model.notebooks.first { $0.title == "A" })
        let b = try XCTUnwrap(model.notebooks.first { $0.title == "B" })
        let outside = try XCTUnwrap(model.notebooks.first { $0.title == "Outside" })
        let workspace = DocumentWorkspace(context: container.mainContext, storage: storage, defaults: defaults)
        await workspace.restore()
        _ = await workspace.open(outside); _ = await workspace.open(b); _ = await workspace.open(a)
        workspace.activeSession?.changed(PKDrawing())
        let ids = Set(model.documents(inSubtreeOf: folder).map(\.id))
        let forgotten = await workspace.forget(ids)
        XCTAssertTrue(forgotten)
        XCTAssertEqual(workspace.openNotebooks.map(\.id), [outside.id])
        XCTAssertNil(workspace.activeSession)
        let inkPath = try XCTUnwrap(a.pages.first?.drawingFilePath)
        let before = try await storage.read(inkPath)
        model.delete(folder)
        XCTAssertTrue(a.isInTrash)
        let restoredWorkspace = DocumentWorkspace(context: container.mainContext, storage: storage, defaults: defaults)
        await restoredWorkspace.restore()
        XCTAssertFalse(restoredWorkspace.openNotebooks.contains { $0.id == a.id })
        let rejected = await restoredWorkspace.open(a)
        XCTAssertFalse(rejected)
        model.restore(folder)
        let reopened = await restoredWorkspace.open(a)
        XCTAssertTrue(reopened)
        let after = try await storage.read(inkPath)
        XCTAssertEqual(before, after)
        XCTAssertEqual(a.folder?.id, child.id)
    }

    func testPDFImportRejectsTrashedDestination() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("test.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).writePDF(to: source) { $0.beginPage() }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        XCTAssertTrue(model.createFolder(title: "Removed"))
        let folder = try XCTUnwrap(model.folders.first)
        model.delete(folder)
        await model.importPDF(from: source, folder: folder, storage: storage)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Notebook>()), 0)
        XCTAssertTrue(model.errorMessage?.contains("Restore the containing folder") == true)
    }

    func testFolderRemovalIsBlockedIfActiveInkCannotBeSaved() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: root)
        let suite = "OrganizationTabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext)
        XCTAssertTrue(model.createFolder(title: "Folder"))
        let folder = try XCTUnwrap(model.folders.first)
        XCTAssertTrue(model.createNotebook(title: "Ink", color: .sage, template: .blank, folder: folder))
        let notebook = try XCTUnwrap(model.notebooks.first)
        let workspace = DocumentWorkspace(context: container.mainContext, storage: DrawingStorage(root: root), defaults: defaults)
        await workspace.restore(); _ = await workspace.open(notebook)
        workspace.activeSession?.changed(PKDrawing())
        let forgotten = await workspace.forget(Set([notebook.id]))
        XCTAssertFalse(forgotten)
        XCTAssertEqual(workspace.activeID, notebook.id)
        XCTAssertFalse(folder.isInTrash)
    }
}
