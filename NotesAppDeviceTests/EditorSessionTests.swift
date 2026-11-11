import XCTest
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class EditorSessionTests: XCTestCase {
    func testConcurrentFlushesKeepNewestDrawing() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Concurrent saves"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let storage = DrawingStorage(root: root)
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        let point = PKStrokePoint(location: CGPoint(x: 20, y: 20), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [point], creationDate: .now))
        session.changed(PKDrawing(strokes: [stroke]))
        XCTAssertTrue(session.hasPendingSave)
        let first = Task { await session.flush() }
        await Task.yield()
        session.changed(PKDrawing(strokes: [stroke, stroke]))
        let second = Task { await session.flush() }
        let firstResult = await first.value, secondResult = await second.value
        XCTAssertTrue(firstResult); XCTAssertTrue(secondResult)
        let data = try await storage.read(try XCTUnwrap(page.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: data).strokes.count, 2)
        XCTAssertEqual(session.status, "Saved on iPad")
        XCTAssertFalse(session.hasPendingSave)
    }

    func testDebounceCoalescesChangesIntoOneCheckpoint() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Debounce"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let storage = DrawingStorage(root: root)
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        for _ in 0..<4 {
            session.changed(PKDrawing())
            try await Task.sleep(for: .milliseconds(40))
        }
        // Await observable persistence, not a hard performance threshold on the simulator.
        for _ in 0..<100 {
            if page.drawingFilePath != nil, session.status == "Saved on iPad" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let path = try XCTUnwrap(page.drawingFilePath)
        let data = try await storage.read(path)
        XCTAssertNoThrow(try PKDrawing(data: data))
        let extraCheckpoint = try await storage.exists(path + ".backup")
        XCTAssertFalse(extraCheckpoint)
        XCTAssertFalse(session.hasPendingSave)
    }

    func testSwipeThresholdAndDirection() {
        XCTAssertEqual(PageSwipe.direction(translation: CGPoint(x: -150, y: 10), viewportWidth: 768), 1)
        XCTAssertEqual(PageSwipe.direction(translation: CGPoint(x: 150, y: 10), viewportWidth: 768), -1)
        XCTAssertNil(PageSwipe.direction(translation: CGPoint(x: -30, y: 0), viewportWidth: 768))
        XCTAssertNil(PageSwipe.direction(translation: CGPoint(x: -150, y: 180), viewportWidth: 768))
    }

    func testPagingCreatesOnlyAfterLastPageAndKeepsTemplate() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Paging")
        let page = NotePage(pageIndex: 0, paperTemplate: .grid)
        container.mainContext.insert(notebook); container.mainContext.insert(page)
        notebook.pages = [page]
        try container.mainContext.save()
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        await session.turnPage(-1, creatingIfNeeded: true)
        XCTAssertEqual(notebook.pages.count, 1)
        await session.turnPage(1) // Arrow navigation must not create a page.
        XCTAssertEqual(notebook.pages.count, 1)
        await session.turnPage(1, creatingIfNeeded: true)
        XCTAssertEqual(notebook.pages.count, 2)
        XCTAssertEqual(session.page?.paperTemplate, .grid)
        XCTAssertEqual(session.page?.pageIndex, 1)
        await session.turnPage(-1, creatingIfNeeded: true)
        XCTAssertEqual(session.page?.id, page.id)
        XCTAssertEqual(session.pageTurnDirection, -1)
        await session.turnPage(1, creatingIfNeeded: true)
        XCTAssertEqual(notebook.pages.count, 2)
    }

    func testInkRoundTripAndImmediatePageSwitchFlush() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Test")
        container.mainContext.insert(notebook)
        let first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 1)
        container.mainContext.insert(first); container.mainContext.insert(second)
        notebook.pages = [first, second]
        try container.mainContext.save()
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(first)
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 80)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        session.changed(ink)
        // Switch before debounce can fire; open must flush the first page.
        await session.open(second)
        XCTAssertEqual(session.page?.id, second.id)
        XCTAssertEqual(session.drawing.strokes.count, 0)
        // The outgoing canvas can still exist during the slide. Its callbacks must be ignored.
        let outgoing = InkCanvas()
        outgoing.pageID = first.id
        outgoing.drawing = ink
        PaperCanvas.Coordinator(session: session).canvasViewDrawingDidChange(outgoing)
        XCTAssertEqual(session.drawing.strokes.count, 0)
        XCTAssertEqual(session.status, "Saved on iPad")
        let path = try XCTUnwrap(first.drawingFilePath)
        let data = try await storage.read(path)
        XCTAssertEqual(try PKDrawing(data: data).strokes.count, 1)
        await session.open(first)
        XCTAssertEqual(session.drawing.strokes.count, 1)
        await session.duplicatePage()
        XCTAssertEqual(session.drawing.strokes.count, 1)
        XCTAssertNotEqual(session.page?.drawingFilePath, first.drawingFilePath)
    }

    func testCorruptPageCannotOverwriteSourceAndBackupCanRecover() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Recovery"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page)
        notebook.pages = [page]
        let path = DrawingStorage.path(notebook: notebook.id, page: page.id)
        page.drawingFilePath = path
        try container.mainContext.save()
        try await storage.write(PKDrawing().dataRepresentation(), to: path)
        try await storage.write(Data([0, 1, 2]), to: path)
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        XCTAssertFalse(session.ready)
        let saved = await session.flush()
        XCTAssertTrue(saved)
        let corrupt = try await storage.read(path)
        XCTAssertEqual(corrupt, Data([0, 1, 2]))
        await session.recover()
        XCTAssertTrue(session.ready)
        let recovered = try await storage.read(path)
        XCTAssertNoThrow(try PKDrawing(data: recovered))
    }

    func testFailedSaveBlocksNavigationAndKeepsPendingChanges() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: root) // A file cannot serve as the document directory.
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Failure"), page = NotePage(pageIndex: 0), next = NotePage(pageIndex: 1)
        container.mainContext.insert(notebook); container.mainContext.insert(page); container.mainContext.insert(next)
        notebook.pages = [page, next]
        try container.mainContext.save()
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: DrawingStorage(root: root))
        await session.open(page)
        session.changed(PKDrawing())
        await session.open(next)
        XCTAssertEqual(session.page?.id, page.id)
        XCTAssertEqual(session.status, "Save failed — retry")
        XCTAssertTrue(session.hasPendingSave)
        XCTAssertNotNil(session.errorMessage)
    }
}
