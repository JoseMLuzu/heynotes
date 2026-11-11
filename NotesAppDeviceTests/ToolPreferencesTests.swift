import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class ToolPreferencesTests: XCTestCase {
    func testIndependentToolsPersistColorsWidthsAndOpacity() throws {
        let suite = "NotesToolTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ToolPreferences(defaults: defaults)
        settings.selected = .pen
        settings.ink.width = 5
        settings.ink.opacity = 0.4
        settings.setColor(.red)
        let pen = settings.ink
        settings.selected = .marker
        settings.ink.width = 24
        settings.setColor(.yellow)
        let marker = settings.ink
        settings.selected = .pencil
        settings.ink.width = 2
        settings.setColor(.blue)
        let pencil = settings.ink
        let reopened = ToolPreferences(defaults: defaults)
        XCTAssertEqual(reopened.selected, .pencil)
        XCTAssertEqual(reopened.ink, pencil)
        reopened.selected = .pen
        XCTAssertEqual(reopened.ink, pen)
        let tool = try XCTUnwrap(reopened.tool as? PKInkingTool)
        XCTAssertEqual(tool.inkType, .pen)
        XCTAssertEqual(tool.width, pen.width, accuracy: 0.001)
        XCTAssertEqual(tool.color.cgColor.alpha, 0.4, accuracy: 0.001)
        reopened.selected = .marker
        XCTAssertEqual(reopened.ink, marker)
        reopened.resetCurrentTool()
        XCTAssertNotEqual(reopened.ink, marker)
        reopened.selected = .pen
        XCTAssertEqual(reopened.ink, pen)
    }

    func testPreciseAndStrokeEraserUseNativeModesAndValidWidths() throws {
        let suite = "NotesToolTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ToolPreferences(defaults: defaults)
        settings.selected = .eraser
        XCTAssertEqual((settings.tool as? PKEraserTool)?.eraserType, .vector)
        settings.eraserMode = .precise
        settings.eraserWidth = 30
        let precise = try XCTUnwrap(settings.tool as? PKEraserTool)
        XCTAssertEqual(precise.eraserType, .fixedWidthBitmap)
        XCTAssertEqual(precise.width, settings.eraserWidth, accuracy: 0.001)
        settings.eraserWidth = 10000
        XCTAssertEqual(settings.eraserWidth, settings.eraserRange.upperBound)
        let reopened = ToolPreferences(defaults: defaults)
        XCTAssertEqual(reopened.eraserMode, .precise)
        XCTAssertEqual(reopened.eraserWidth, settings.eraserWidth)
        reopened.selected = .pen
        reopened.ink.width = -30
        XCTAssertEqual(reopened.ink.width, reopened.widthRange.lowerBound)
        reopened.ink.opacity = 10
        XCTAssertEqual(reopened.ink.opacity, 1)
    }

    func testClearHandwritingCanUndoRedoAndSaveWithoutChangingBackground() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Clear"), page = NotePage(pageIndex: 0, paperTemplate: .grid)
        container.mainContext.insert(notebook); container.mainContext.insert(page)
        notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        let canvas = InkCanvas()
        canvas.pageID = page.id; canvas.drawing = ink
        session.canvas = canvas; session.changed(ink)
        let saved = await session.flush()
        XCTAssertTrue(saved)
        // A background reference must be unaffected by clearing the ink layer.
        page.pdfFilePath = "Sources/kept.pdf"; page.pdfPageIndex = 0
        canvas.undoManager?.removeAllActions()
        session.clearHandwriting()
        XCTAssertEqual(canvas.drawing.strokes.count, 0)
        XCTAssertEqual(session.drawing.strokes.count, 0)
        XCTAssertTrue(canvas.undoManager?.canUndo == true)
        canvas.undoManager?.undo()
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertEqual(session.drawing.strokes.count, 1)
        canvas.undoManager?.redo()
        XCTAssertEqual(canvas.drawing.strokes.count, 0)
        XCTAssertEqual(session.drawing.strokes.count, 0)
        let flushed = await session.flush()
        XCTAssertTrue(flushed)
        let data = try await storage.read(try XCTUnwrap(page.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: data).strokes.count, 0)
        XCTAssertEqual(page.pdfFilePath, "Sources/kept.pdf")
        XCTAssertEqual(page.paperTemplate, .grid)
    }
}
