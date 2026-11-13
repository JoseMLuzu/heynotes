import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class PageLoadingTests: XCTestCase {
    func testZoomedProgrammaticTurnMovesOldPaperFullyOutOfViewport() throws {
        let container = PageCanvasContainer(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let first = CanvasHost(), second = CanvasHost()
        container.show(first, pageID: UUID(), direction: 1, reduceMotion: false)
        container.layoutIfNeeded(); first.layoutIfNeeded()
        first.setZoomScale(2, animated: false)
        let renderedWidth = first.pageSize.width * first.zoomScale
        XCTAssertGreaterThan(renderedWidth, container.bounds.width)
        container.show(second, pageID: UUID(), direction: 1, reduceMotion: false)
        XCTAssertEqual(container.turnDistance, renderedWidth + 16)
        let animation = try XCTUnwrap(container.animator)
        animation.stopAnimation(false); animation.finishAnimation(at: .end)
        XCTAssertNil(first.superview)
        XCTAssertTrue(container.current === second)
    }

    func testRealSheetSlideRendersBothDirectionsWithoutMovingViewport() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 840)
        let controller = UIViewController()
        let container = PageCanvasContainer(frame: window.bounds)
        controller.view = container; window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let first = CanvasHost(), firstID = UUID()
        first.paper.template = .grid; first.ink.drawing = ink()
        var label = PageElement(kind: .text, rect: CGRect(x: 90, y: 220, width: 400, height: 100))
        label.text = "Page 1"; label.fontSize = 64
        first.objectContent.elements = [label]
        container.show(first, pageID: firstID, direction: 1, reduceMotion: false)
        container.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        for direction in [1, -1] {
            let outgoing = try XCTUnwrap(container.current)
            let incoming = CanvasHost()
            incoming.paper.template = direction == 1 ? .blank : .grid
            incoming.ink.drawing = ink()
            label.text = direction == 1 ? "Page 2" : "Page 1"
            incoming.objectContent.elements = [label]
            let oldZoom = outgoing.zoomScale, oldSize = outgoing.contentSize
            outgoing.setPageOffset(CGFloat(-direction) * 24)
            container.prepareTurn(from: try XCTUnwrap(container.pageID), direction: direction, reduceMotion: false, velocity: CGFloat(-direction) * 1400)
            container.show(incoming, pageID: UUID(), direction: direction, reduceMotion: false)
            let animator = try XCTUnwrap(container.animator)
            animator.pauseAnimation(); animator.fractionComplete = 0.28
            try await Task.sleep(for: .milliseconds(60))
            XCTAssertEqual(outgoing.frame, container.bounds); XCTAssertEqual(incoming.frame, container.bounds)
            XCTAssertEqual(outgoing.zoomScale, oldZoom); XCTAssertEqual(outgoing.contentSize, oldSize)
            XCTAssertEqual(outgoing.alpha, 1); XCTAssertEqual(incoming.alpha, 1)
            XCTAssertEqual(outgoing.transform, .identity); XCTAssertEqual(incoming.transform, .identity)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = direction == 1 ? "Sheet-Slide-Forward" : "Sheet-Slide-Back"
            attachment.lifetime = .keepAlways; add(attachment)
            animator.stopAnimation(false); animator.finishAnimation(at: .end)
            XCTAssertNil(outgoing.superview)
            XCTAssertTrue(incoming.ink.isUserInteractionEnabled)
        }
    }

    func testFullSheetTurnPreservesPullAndQueuesOneFollowUpWithoutReplacingInk() throws {
        let container = PageCanvasContainer(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let first = CanvasHost(), second = CanvasHost(), firstID = UUID(), secondID = UUID()
        let drawing = ink()
        first.ink.drawing = drawing; second.ink.drawing = drawing
        container.show(first, pageID: firstID, direction: 1, reduceMotion: false)
        container.layoutIfNeeded(); first.layoutIfNeeded()
        first.setPageOffset(-24)
        container.prepareTurn(from: firstID, direction: 1, reduceMotion: false, velocity: -4000)
        XCTAssertEqual(first.visiblePageOffset, -24, accuracy: 0.01)
        container.show(second, pageID: secondID, direction: 1, reduceMotion: false)
        XCTAssertEqual(container.turnDistance, 656)
        XCTAssertEqual(container.turnDuration, 0.16)
        XCTAssertEqual(container.alpha, 1); XCTAssertEqual(second.alpha, 1)
        XCTAssertTrue(container.current === second)
        XCTAssertEqual(second.ink.drawing, drawing)
        var calls = 0
        let animation = try XCTUnwrap(container.animator)
        container.afterCurrentTurn { calls += 10 }
        XCTAssertLessThanOrEqual(try XCTUnwrap(container.followUpTailDuration), 0.06)
        XCTAssertTrue(container.animator === animation)
        container.afterCurrentTurn { calls += 1 }
        XCTAssertEqual(calls, 0)
        animation.stopAnimation(false); animation.finishAnimation(at: .end)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(first.superview); XCTAssertNil(container.animator)
        XCTAssertTrue(second.ink.isUserInteractionEnabled)
        XCTAssertEqual(second.visiblePageOffset, 0, accuracy: 0.01)
        XCTAssertEqual(second.ink.drawing, drawing)
    }

    func testResizeCancelsQueuedGestureAndReduceMotionReplacesDirectly() throws {
        let container = PageCanvasContainer(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let first = CanvasHost(), second = CanvasHost()
        container.show(first, pageID: UUID(), direction: 1, reduceMotion: false)
        container.layoutIfNeeded()
        container.show(second, pageID: UUID(), direction: -1, reduceMotion: false)
        XCTAssertLessThan(container.turnDistance, 0)
        var called = false
        container.afterCurrentTurn { called = true }
        container.bounds.size = CGSize(width: 700, height: 500)
        container.setNeedsLayout(); container.layoutIfNeeded()
        XCTAssertFalse(called)
        XCTAssertNil(container.animator); XCTAssertNil(first.superview)
        XCTAssertEqual(second.visiblePageOffset, 0, accuracy: 0.01)
        let third = CanvasHost()
        container.show(third, pageID: UUID(), direction: 1, reduceMotion: true)
        XCTAssertNil(container.animator); XCTAssertNil(second.superview)
        XCTAssertEqual(container.turnDistance, 0); XCTAssertEqual(container.turnDuration, 0)
        XCTAssertTrue(third.ink.isUserInteractionEnabled)
    }

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
