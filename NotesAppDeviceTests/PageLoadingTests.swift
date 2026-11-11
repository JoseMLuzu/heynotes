import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class PageLoadingTests: XCTestCase {
    func testCurrentPageReloadNeverUsesAnOlderCheckpoint() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let storage = DrawingStorage(root: root)
        let notebook = Notebook(title: "Reload"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page)
        notebook.pages = [page]; try container.mainContext.save()
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        session.changed(PKDrawing())
        let checkpoint = await session.flush(); XCTAssertTrue(checkpoint)
        session.changed(ink())
        await session.open(page)
        XCTAssertTrue(session.ready)
        XCTAssertEqual(session.drawing.strokes.count, 1)
        let data = try await storage.read(try XCTUnwrap(page.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: data).strokes.count, 1)
    }

    func testAliasedLegacyDrawingPathWaitsForOutgoingSave() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let storage = DrawingStorage(root: root)
        let notebook = Notebook(title: "Legacy alias"), first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 1)
        container.mainContext.insert(notebook); container.mainContext.insert(first); container.mainContext.insert(second)
        notebook.pages = [first, second]
        first.drawingFilePath = "legacy.drawing"; second.drawingFilePath = "legacy.drawing"
        try await storage.write(PKDrawing().dataRepresentation(), to: "legacy.drawing")
        try container.mainContext.save()
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(first)
        session.changed(ink())
        await session.open(second)
        XCTAssertTrue(session.ready)
        XCTAssertEqual(session.page?.id, second.id)
        XCTAssertEqual(session.drawing.strokes.count, 1)
    }

    func testTransitionKeepsFingerPagingAvailableAndResizeFinishesCleanly() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let controller = UIViewController()
        let container = PageCanvasContainer(frame: window.bounds)
        controller.view = container; window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let first = CanvasHost(), second = CanvasHost(), firstID = UUID()
        container.show(first, pageID: firstID, direction: 1, reduceMotion: false)
        container.prepareTurn(from: firstID, direction: 1, reduceMotion: false)
        XCTAssertEqual(first.alpha, 1)
        XCTAssertEqual(first.transform, .identity)
        container.show(second, pageID: UUID(), direction: 1, reduceMotion: false)
        XCTAssertTrue(container.isOpaque)
        XCTAssertEqual(first.alpha, 1); XCTAssertEqual(second.alpha, 1)
        XCTAssertEqual(first.frame, container.bounds); XCTAssertEqual(second.frame, container.bounds)
        XCTAssertTrue(second.isUserInteractionEnabled)
        XCTAssertFalse(second.ink.isUserInteractionEnabled)
        second.editorAllowsInk = true
        XCTAssertFalse(second.ink.isUserInteractionEnabled)
        container.setNeedsLayout(); container.layoutIfNeeded()
        XCTAssertFalse(second.ink.isUserInteractionEnabled) // A routine layout must not snap the animation to its end.
        second.editorAllowsInk = false
        container.bounds.size = CGSize(width: 700, height: 500)
        container.setNeedsLayout(); container.layoutIfNeeded()
        XCTAssertFalse(second.ink.isUserInteractionEnabled) // Finishing motion must respect a disabled editor.
        second.editorAllowsInk = true
        XCTAssertTrue(second.ink.isUserInteractionEnabled)
        XCTAssertNil(first.superview)
        XCTAssertEqual(second.frame, container.bounds)
    }

    func testPaperMovementKeepsZoomViewportAndInkGeometryStable() throws {
        let host = CanvasHost()
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        host.layoutIfNeeded()
        let zoomRoot = try XCTUnwrap(host.viewForZooming(in: host))
        let frame = zoomRoot.frame, contentSize = host.contentSize, scale = host.zoomScale
        let point = CGPoint(x: 100, y: 150)
        let original = host.ink.convert(point, to: host)
        host.setPageOffset(24)
        let shifted = host.ink.convert(point, to: host)
        XCTAssertEqual(shifted.x - original.x, 24, accuracy: 0.01)
        XCTAssertEqual(shifted.y, original.y, accuracy: 0.01)
        XCTAssertEqual(zoomRoot.frame, frame)
        XCTAssertEqual(host.contentSize, contentSize)
        XCTAssertEqual(host.zoomScale, scale)
        XCTAssertEqual(host.transform, .identity)
        XCTAssertEqual(host.alpha, 1)
        host.setPageOffset(0)
        let restored = host.ink.convert(point, to: host)
        XCTAssertEqual(restored.x, original.x, accuracy: 0.01)
        XCTAssertEqual(restored.y, original.y, accuracy: 0.01)
    }

    private func ink() -> PKDrawing {
        let points = [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 90)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }
}
