import XCTest
import SwiftUI
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class InteractivePageTests: XCTestCase {
    func testDragDoesNotCommitUntilReleaseAndReverseCanCancel() {
        let host = CanvasHost()
        host.ink.pageID = UUID(); host.hasNextPage = true
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 840); host.layoutIfNeeded()
        let pan = ControlledPagePan()
        var turns: [Int] = [], pulls: [CGFloat] = [], cancellations = 0
        host.onPageSwipe = { turns.append($0); XCTAssertFalse($1) }
        host.onPagePull = { pulls.append($0) }
        host.onPagePullCancelled = { cancellations += 1 }
        pan.sampleState = .began; pan.x = -20; host.handlePagePan(pan)
        pan.sampleState = .changed; pan.x = -180; host.handlePagePan(pan)
        XCTAssertTrue(turns.isEmpty); XCTAssertEqual(host.visiblePageOffset, -180)
        pan.x = -8; pan.speed = 600; host.handlePagePan(pan)
        pan.sampleState = .ended; host.handlePagePan(pan)
        XCTAssertTrue(turns.isEmpty); XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(pulls, [-20, -180, -8])
        pan.sampleState = .began; pan.x = -20; pan.speed = -900; host.handlePagePan(pan)
        XCTAssertTrue(turns.isEmpty)
        pan.sampleState = .ended; host.handlePagePan(pan)
        XCTAssertEqual(turns, [1]) // A short flick still turns without a long drag.
    }

    func testPreparedSheetsFollowFingerInBothDirectionsAndCancelPreservesInk() async throws {
        let fixture = try InteractiveFixture()
        defer { fixture.cleanup() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene), controller = UIViewController()
        window.frame = fixture.container.bounds
        controller.view = fixture.container; window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let container = fixture.container, active = try XCTUnwrap(container.current)
        let originalID = container.pageID, drawing = active.ink.drawing
        let next = fixture.prepared(2), previous = fixture.prepared(0)
        container.prepare(next); container.prepare(previous)
        try await wait { container.preparedCanvasCount == 2 }
        for (translation, target) in [(CGFloat(-220), next), (CGFloat(100), previous)] {
            active.setPageOffset(translation)
            container.updateInteractivePull(from: fixture.pages[1].id, translation: translation)
            let preview = try XCTUnwrap(container.interactiveNeighbor)
            XCTAssertEqual(preview.ink.pageID, target.id)
            let sign: CGFloat = translation < 0 ? 1 : -1
            XCTAssertEqual(preview.visiblePageOffset, sign * 656 + translation, accuracy: 0.01)
            XCTAssertFalse(preview.isUserInteractionEnabled)
            XCTAssertTrue(preview.accessibilityElementsHidden)
            XCTAssertEqual(container.pageID, originalID)
            XCTAssertTrue(container.current === active)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = translation < 0 ? "Interactive-Forward-Pull" : "Interactive-Reverse-Pull"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        container.cancelInteractivePull()
        let animator = try XCTUnwrap(container.animator)
        animator.stopAnimation(false); animator.finishAnimation(at: .end)
        XCTAssertEqual(active.visiblePageOffset, 0, accuracy: 0.01)
        XCTAssertTrue(active.ink.isUserInteractionEnabled)
        XCTAssertEqual(active.ink.drawing, drawing)
        XCTAssertEqual(container.preparedCanvasCount, 2)
        XCTAssertEqual(container.pageID, originalID)
    }

    func testVersionMismatchRejectsStaleCanvasAndMemoryWarningReleasesNeighbors() async throws {
        let fixture = try InteractiveFixture()
        defer { fixture.cleanup() }
        let container = fixture.container, prepared = fixture.prepared(2)
        container.prepare(prepared)
        try await wait { container.preparedCanvasCount == 1 }
        XCTAssertNil(container.takePreparedCanvas(pageID: prepared.id, identity: UUID(), size: prepared.size))
        XCTAssertEqual(container.preparedCanvasCount, 0)
        container.prepare(prepared)
        try await wait { container.preparedCanvasCount == 1 }
        container.current?.setPageOffset(-120)
        container.updateInteractivePull(from: fixture.pages[1].id, translation: -120)
        weak let released = container.interactiveNeighbor
        container.discardPreparedCanvases()
        if let animator = container.animator { animator.stopAnimation(false); animator.finishAnimation(at: .end) }
        XCTAssertEqual(container.preparedCanvasCount, 0); XCTAssertNil(container.interactiveNeighbor)
        try await wait { released == nil }
        XCTAssertNil(released)
        XCTAssertNotNil(container.current)
        XCTAssertEqual(container.current?.ink.pageID, fixture.pages[1].id)
    }

    func testRotationDuringPullResetsBothSheetsWithoutChangingIdentityOrPermission() async throws {
        let fixture = try InteractiveFixture()
        defer { fixture.cleanup() }
        let container = fixture.container, active = try XCTUnwrap(container.current)
        let target = fixture.prepared(2)
        container.prepare(target)
        try await wait { container.preparedCanvasCount == 1 }
        active.setPageOffset(-180)
        container.updateInteractivePull(from: fixture.pages[1].id, translation: -180)
        let preview = try XCTUnwrap(container.interactiveNeighbor)
        active.editorAllowsInk = false
        container.bounds.size = CGSize(width: 840, height: 640)
        container.setNeedsLayout(); container.layoutIfNeeded()
        XCTAssertNil(container.interactiveNeighbor); XCTAssertNil(container.animator)
        XCTAssertEqual(container.pageID, fixture.pages[1].id)
        XCTAssertEqual(active.visiblePageOffset, 0, accuracy: 0.01)
        XCTAssertEqual(preview.frame, container.bounds)
        XCTAssertGreaterThanOrEqual(preview.visiblePageOffset, container.bounds.width)
        XCTAssertFalse(active.ink.isUserInteractionEnabled)
        active.editorAllowsInk = true
        XCTAssertTrue(active.ink.isUserInteractionEnabled)
    }

    func testSwiftUIActivatesSamePreparedCanvasAfterSavingOutgoingInk() async throws {
        let fixture = try InteractiveFixture()
        defer { fixture.cleanup() }
        let session = EditorSession(notebook: fixture.notebook, context: fixture.store.mainContext, storage: fixture.storage)
        defer { session.discardPreparedPages(); withExtendedLifetime(fixture.store) {} }
        await session.open(fixture.pages[1])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 840)
        let controller = UIHostingController(rootView: ObservedTestCanvas(session: session))
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { self.findContainer(controller.view)?.preparedCanvasCount == 2 }
        let container = try XCTUnwrap(findContainer(controller.view)), original = try XCTUnwrap(container.current)
        let oldDrawing = fixture.drawing
        original.ink.drawing = oldDrawing; session.changed(oldDrawing)
        original.setPageOffset(-200)
        container.updateInteractivePull(from: fixture.pages[1].id, translation: -200)
        let preview = try XCTUnwrap(container.interactiveNeighbor)
        container.prepareTurn(from: fixture.pages[1].id, direction: 1, reduceMotion: false, velocity: -900)
        await session.turnPage(1)
        try await wait { container.pageID == fixture.pages[2].id }
        XCTAssertTrue(container.current === preview)
        XCTAssertTrue(session.canvas === preview.ink)
        let saved = try await fixture.storage.read(try XCTUnwrap(fixture.pages[1].drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: saved), oldDrawing)
        if let animator = container.animator { animator.stopAnimation(false); animator.finishAnimation(at: .end) }
        XCTAssertTrue(preview.ink.isUserInteractionEnabled)
        await session.turnPage(-1)
        try await wait { container.pageID == fixture.pages[1].id }
        XCTAssertEqual(container.current?.ink.drawing, oldDrawing)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Canvas preparation/update did not complete")
    }
    private func findContainer(_ view: UIView) -> PageCanvasContainer? {
        if let result = view as? PageCanvasContainer { return result }
        return view.subviews.lazy.compactMap { self.findContainer($0) }.first
    }
}

@MainActor private struct ObservedTestCanvas: View {
    let session: EditorSession
    var body: some View {
        let _ = session.page?.id
        PaperCanvas(session: session, tool: PKInkingTool(.pen), fingerDrawing: false).disabled(session.busy)
    }
}

@MainActor private final class ControlledPagePan: UIPanGestureRecognizer {
    var sampleState: State = .possible
    var x: CGFloat = 0
    var speed: CGFloat = -900
    override var state: State { get { sampleState } set { sampleState = newValue } }
    override var numberOfTouches: Int { 1 }
    override func translation(in view: UIView?) -> CGPoint { CGPoint(x: x, y: 0) }
    override func velocity(in view: UIView?) -> CGPoint { CGPoint(x: speed, y: 0) }
}

@MainActor private final class InteractiveFixture {
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store: ModelContainer
    let storage: DrawingStorage
    let notebook = Notebook(title: "Interactive sheets")
    let pages = (0..<3).map { NotePage(pageIndex: $0, paperTemplate: .grid) }
    let container = PageCanvasContainer(frame: CGRect(x: 0, y: 0, width: 640, height: 840))
    let drawing: PKDrawing
    init() throws {
        store = try PersistenceController.makeContainer(inMemory: true)
        storage = DrawingStorage(root: root)
        let points = [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 90)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        store.mainContext.insert(notebook)
        for page in pages { store.mainContext.insert(page) }
        notebook.pages = pages; try store.mainContext.save()
        let active = CanvasHost(); active.ink.pageID = pages[1].id; active.ink.drawing = drawing
        container.show(active, pageID: pages[1].id, direction: 1, reduceMotion: true)
        container.layoutIfNeeded()
        container.retainNeighbors([-1: pages[0].id, 1: pages[2].id])
    }
    func prepared(_ index: Int) -> PreparedCanvasPage {
        PreparedCanvasPage(page: pages[index], content: PreparedPageContent(drawing: drawing, background: nil, elements: [], images: [:]))
    }
    func cleanup() { container.discardPreparedCanvases(); try? FileManager.default.removeItem(at: root) }
}
