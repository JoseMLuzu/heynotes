import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class PageGestureTests: XCTestCase {
    func testObjectToolsLeaveFingerPagingAvailableWithoutStealingObjectDrags() throws {
        let host = CanvasHost()
        host.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        host.layoutIfNeeded()
        host.objectControls.elements = [PageElement(kind: .rectangle, rect: CGRect(x: 40, y: 40, width: 100, height: 100))]
        let swipe = ObjectToolPagePan()
        let direct = NSNumber(value: UITouch.TouchType.direct.rawValue)
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let objectPan = try XCTUnwrap(host.objectControls.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
        for tool in [EditorTool.line, .rectangle, .ellipse, .arrow, .tape, .objects] {
            host.objectControls.tool = tool
            swipe.origin = CGPoint(x: 300, y: 300)
            XCTAssertEqual(host.pagePan.delegate?.gestureRecognizerShouldBegin?(swipe), true, tool.title)
            XCTAssertTrue(objectPan.allowedTouchTypes.contains(pencil))
            XCTAssertEqual(objectPan.allowedTouchTypes.contains(direct), tool == .objects)
            swipe.origin = CGPoint(x: 80, y: 80)
            XCTAssertEqual(host.pagePan.delegate?.gestureRecognizerShouldBegin?(swipe), tool != .objects)
        }
        host.objectControls.tool = .tape
        host.objectControls.fingerDrawing = true
        XCTAssertTrue(objectPan.allowedTouchTypes.contains(direct))
        host.ink.drawingPolicy = .anyInput
        XCTAssertEqual(host.pagePan.delegate?.gestureRecognizerShouldBegin?(swipe), false)
        host.ink.drawingPolicy = .pencilOnly
        host.setZoomScale(host.minimumZoomScale * 1.5, animated: false)
        XCTAssertEqual(host.pagePan.delegate?.gestureRecognizerShouldBegin?(swipe), false)
    }

    func testShortFlicksTurnExistingPagesWithoutRequiringALongDrag() {
        XCTAssertEqual(PageSwipe.direction(translation: CGPoint(x: -20, y: 2), velocity: CGPoint(x: -900, y: 20), viewportWidth: 1024), 1)
        XCTAssertEqual(PageSwipe.direction(translation: CGPoint(x: 20, y: 2), velocity: CGPoint(x: 900, y: 20), viewportWidth: 1024), -1)
        XCTAssertEqual(PageSwipe.direction(translation: CGPoint(x: -12, y: 1), velocity: CGPoint(x: -380, y: 20), viewportWidth: 1024), 1)
        XCTAssertEqual(PageSwipe.direction(translation: CGPoint(x: -60, y: 2), viewportWidth: 768), 1)
        XCTAssertNil(PageSwipe.direction(translation: CGPoint(x: -6, y: 0), velocity: CGPoint(x: -1200, y: 0), viewportWidth: 768))
        XCTAssertNil(PageSwipe.direction(translation: CGPoint(x: -20, y: 18), velocity: CGPoint(x: -900, y: 100), viewportWidth: 768))
        XCTAssertNil(PageSwipe.direction(translation: CGPoint(x: -20, y: 2), velocity: CGPoint(x: 900, y: 20), viewportWidth: 768))
        XCTAssertFalse(PageSwipe.isCreationPull(CGPoint(x: -20, y: 0), viewportWidth: 768))
        XCTAssertFalse(PageSwipe.isCreationPull(CGPoint(x: -100, y: 100), viewportWidth: 768))
        XCTAssertFalse(PageSwipe.isCreationPull(CGPoint(x: 100, y: 0), viewportWidth: 768))
        XCTAssertTrue(PageSwipe.isCreationPull(CGPoint(x: -100, y: 4), viewportWidth: 768))
    }

    func testCreationRequiresContinuousHoldAndCommitsOncePerGesture() {
        var hold = PageCreationHold()
        XCTAssertEqual(hold.update(eligible: true, now: 0), .progress(0))
        guard case .progress(let progress) = hold.update(eligible: true, now: 0.49) else { return XCTFail("Committed too early") }
        XCTAssertLessThan(progress, 1)
        XCTAssertEqual(hold.update(eligible: true, now: 0.5), .commit)
        XCTAssertEqual(hold.update(eligible: true, now: 50), .inactive)
        XCTAssertFalse(hold.isWaiting)
        hold.cancel()
        XCTAssertEqual(hold.update(eligible: true, now: 60), .inactive)
        hold.reset()
        XCTAssertEqual(hold.update(eligible: true, now: 100), .progress(0))
    }

    func testLiftingReversingOrLosingEligibilityRestartsTheHold() {
        var hold = PageCreationHold()
        _ = hold.update(eligible: true, now: 10)
        XCTAssertEqual(hold.update(eligible: false, now: 10.4), .inactive)
        XCTAssertFalse(hold.isWaiting)
        XCTAssertEqual(hold.update(eligible: true, now: 20), .progress(0))
        XCTAssertNotEqual(hold.update(eligible: true, now: 20.49), .commit)
        XCTAssertEqual(hold.update(eligible: true, now: 20.501), .commit)
        hold.reset()
        _ = hold.update(eligible: true, now: 20)
        hold.cancel()
        XCTAssertEqual(hold.update(eligible: true, now: 30), .progress(0))
    }

    func testLastPageFlickNeverCreatesAndCompletedHoldSavesInkBeforeAdding() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Intentional pages"), original = NotePage(pageIndex: 0, paperTemplate: .grid)
        original.pageWidth = 600; original.pageHeight = 800
        container.mainContext.insert(notebook); container.mainContext.insert(original)
        notebook.pages = [original]; try container.mainContext.save()
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(original)
        let points = [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 90)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        session.changed(PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))]))
        let flick = try XCTUnwrap(PageSwipe.direction(translation: CGPoint(x: -20, y: 0), velocity: CGPoint(x: -900, y: 0), viewportWidth: 768))
        await session.turnPage(flick, creatingIfNeeded: false)
        XCTAssertEqual(notebook.pages.count, 1)
        XCTAssertEqual(session.page?.id, original.id)
        var hold = PageCreationHold()
        for time in [0.0, 0.2, 0.49, 0.5, 1, 4] {
            if hold.update(eligible: true, now: time) == .commit { await session.turnPage(1, creatingIfNeeded: true) }
        }
        XCTAssertEqual(notebook.pages.count, 2)
        XCTAssertNotEqual(session.page?.id, original.id)
        XCTAssertEqual(session.page?.paperTemplate, .grid)
        XCTAssertEqual(session.page?.pageWidth, 600); XCTAssertEqual(session.page?.pageHeight, 800)
        let data = try await storage.read(try XCTUnwrap(original.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: data).strokes.count, 1)
        await session.turnPage(-1)
        XCTAssertEqual(session.page?.id, original.id)
        XCTAssertEqual(session.drawing.strokes.count, 1)
    }
}

/// Exercises the real page recognizer delegate with a controlled direct-touch sample.
@MainActor private final class ObjectToolPagePan: UIPanGestureRecognizer {
    var origin = CGPoint.zero
    override var numberOfTouches: Int { 1 }
    override func location(in view: UIView?) -> CGPoint { origin }
    override func translation(in view: UIView?) -> CGPoint { .zero }
    override func velocity(in view: UIView?) -> CGPoint { CGPoint(x: -900, y: 0) }
}
