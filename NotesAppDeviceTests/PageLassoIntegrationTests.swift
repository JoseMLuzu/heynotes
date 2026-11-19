import XCTest
import SwiftData
import SwiftUI
import PencilKit
@testable import NotesApp

@MainActor final class PageLassoIntegrationTests: XCTestCase {
    func testActualEditorMovesMixedSelectionWithOneUndoAndPersistsTheResult() async throws {
        let f = try LassoFixture(); defer { f.cleanup() }; try await f.open()
        let drawing = f.canvas.drawing, items = f.session.elements
        f.overlay.select(points: f.loop)
        try await f.waitForSelection()
        XCTAssertEqual(f.overlay.selection?.strokeIndices.count, 1)
        XCTAssertEqual(f.overlay.selection?.elementIDs, Set(items.map(\.id)))
        XCTAssertEqual(f.canvas.drawing, drawing, "Selecting/previewing must not mutate persisted ink")
        XCTAssertEqual(f.canvas.alpha, 0)
        let selectedImage = UIGraphicsImageRenderer(size: f.window.bounds.size).image { _ in f.window.drawHierarchy(in: f.window.bounds, afterScreenUpdates: true) }
        let selectedAttachment = XCTAttachment(image: selectedImage); selectedAttachment.name = "Mixed-lasso-before-move"
        selectedAttachment.lifetime = .keepAlways; add(selectedAttachment)
        f.overlay.finishMove(CGPoint(x: 32, y: 24))
        XCTAssertEqual(f.session.elements.map(\.id), items.map(\.id))
        XCTAssertEqual(f.session.elements.map(\.x), items.map { $0.x + 32 })
        XCTAssertEqual(f.session.elements.map(\.y), items.map { $0.y + 24 })
        XCTAssertEqual(f.session.drawing.strokes[0].transform, drawing.strokes[0].transform.concatenating(CGAffineTransform(translationX: 32, y: 24)))
        let moved = f.session.drawing, movedItems = f.session.elements
        f.canvas.undoManager?.undo(); XCTAssertEqual(f.session.drawing, drawing); XCTAssertEqual(f.session.elements, items)
        f.canvas.undoManager?.redo(); XCTAssertEqual(f.session.drawing, moved); XCTAssertEqual(f.session.elements, movedItems)
        let saved = await f.session.flush(); XCTAssertTrue(saved)
        let bytes = try await f.session.storage.read(try XCTUnwrap(f.page.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: bytes), moved)
        XCTAssertEqual(try PageElementsCodec.decode(f.page.objectsData), movedItems)
        let render = UIGraphicsImageRenderer(size: f.window.bounds.size).image { _ in f.window.drawHierarchy(in: f.window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: render); attachment.name = "Mixed-lasso-selection-editor"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCancelledPreviewBackgroundAndStaleCommandsKeepRealPageUntouched() async throws {
        let f = try LassoFixture(); defer { f.cleanup() }; try await f.open()
        let drawing = f.canvas.drawing, items = f.session.elements
        f.overlay.select(points: f.loop); try await f.waitForSelection()
        let selection = try XCTUnwrap(f.overlay.selection)
        let pan = LassoTestPan(); pan.origin = CGPoint(x: selection.bounds.midX, y: selection.bounds.midY)
        pan.offset = CGPoint(x: 12, y: 16); pan.phase = .began
        _ = f.overlay.perform(NSSelectorFromString("drag:"), with: pan)
        pan.offset = CGPoint(x: 48, y: 32); pan.phase = .changed
        _ = f.overlay.perform(NSSelectorFromString("drag:"), with: pan)
        XCTAssertTrue(f.session.auxiliaryInputActive)
        XCTAssertEqual(f.canvas.drawing, drawing); XCTAssertEqual(f.session.elements, items)
        let saved = await f.session.flush(); XCTAssertTrue(saved)
        let retained = try await f.session.storage.read(try XCTUnwrap(f.page.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: retained), drawing)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(f.overlay.selection); XCTAssertFalse(f.session.auxiliaryInputActive); XCTAssertEqual(f.canvas.alpha, 1)
        XCTAssertEqual(f.host.objectContent.elements, items)
        let change = selection.moving(by: CGPoint(x: 50, y: 50))
        f.session.busy = true
        XCTAssertFalse(f.session.applyLasso(selection, drawing: change.drawing, elements: change.elements, pageID: f.page.id, action: "Move"))
        f.session.busy = false
        var edited = items; edited[0].text = "A newer edit"; XCTAssertTrue(f.session.replaceElements(edited))
        XCTAssertFalse(f.session.applyLasso(selection, drawing: change.drawing, elements: change.elements, pageID: f.page.id, action: "Move"))
        XCTAssertEqual(f.session.elements, edited); XCTAssertEqual(f.canvas.drawing, drawing)
        // Invalidate a still-running request. It must release the navigation guard.
        f.overlay.update(elements: edited, images: f.session.objectImages)
        f.overlay.select(points: f.loop)
        f.canvas.drawing = PKDrawing()
        try await f.waitForIdle()
        XCTAssertNil(f.overlay.selection); XCTAssertFalse(f.session.auxiliaryInputActive)
        f.canvas.drawing = drawing
    }

    func testDeleteUndoScopePreferencesAndFingerPagingStayIndependent() async throws {
        let f = try LassoFixture(); defer { f.cleanup() }; try await f.open()
        let drawing = f.canvas.drawing, items = f.session.elements
        f.overlay.select(points: f.loop); try await f.waitForSelection()
        XCTAssertTrue(f.overlay.fingerDragEditsSelection(at: CGPoint(x: 180, y: 180)))
        XCTAssertFalse(f.overlay.fingerDragEditsSelection(at: CGPoint(x: 650, y: 800)))
        f.overlay.deleteSelection()
        XCTAssertTrue(f.session.drawing.strokes.isEmpty); XCTAssertTrue(f.session.elements.isEmpty)
        f.canvas.undoManager?.undo(); XCTAssertEqual(f.session.drawing, drawing); XCTAssertEqual(f.session.elements, items)
        f.controls.tools.lassoScope = .handwriting
        await f.settle()
        XCTAssertFalse(f.overlay.active); XCTAssertTrue(f.canvas.isUserInteractionEnabled)
        XCTAssertEqual(f.canvas.alpha, 1); XCTAssertTrue(f.canvas.tool is PKLassoTool)
        let preset = f.controls.tools.capturePreset()
        XCTAssertEqual(preset.lassoScope, .handwriting)
        let saved = ToolPreferences(defaults: f.defaults); XCTAssertEqual(saved.lassoScope, .handwriting)
        saved.lassoScope = .allContent; saved.apply(preset); XCTAssertEqual(saved.lassoScope, .handwriting)
        f.controls.tools.lassoScope = .allContent; await f.settle()
        XCTAssertTrue(f.overlay.active); XCTAssertFalse(f.canvas.isUserInteractionEnabled)
        XCTAssertEqual(f.host.panGestureRecognizer.minimumNumberOfTouches, 2)
        XCTAssertTrue(f.host.pagePan.isEnabled)
        f.overlay.select(points: f.loop); try await f.waitForSelection()
        f.controls.tools.selected = .pen; await f.settle()
        XCTAssertNil(f.overlay.selection); XCTAssertEqual(f.canvas.alpha, 1); XCTAssertTrue(f.canvas.isUserInteractionEnabled)
        f.controls.tools.selected = .lasso
        XCTAssertTrue(f.session.replaceElements([])); await f.settle()
        XCTAssertFalse(f.overlay.active, "Pure-ink pages keep the native lasso even in All Content scope")
        XCTAssertTrue(f.canvas.isUserInteractionEnabled); XCTAssertTrue(f.canvas.tool is PKLassoTool)
        XCTAssertEqual(f.canvas.drawing, drawing)
        XCTAssertTrue(f.session.replaceElements(items)); await f.settle()
        XCTAssertTrue(f.overlay.active)
    }
}

@MainActor private final class LassoFixture {
    private static var containers: [ModelContainer] = []
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "Lasso.\(UUID())"
    let defaults: UserDefaults
    let controls: EditorControlPreferences
    let container: ModelContainer
    let page = NotePage(pageIndex: 0, paperTemplate: .ruled)
    let session: EditorSession
    var window: UIWindow!
    var controller: UIViewController!
    var host: CanvasHost!
    var canvas: InkCanvas { host.ink }
    var overlay: PageLassoOverlay { host.lasso }
    var loop: [CGPoint] { [CGPoint(x: 30, y: 30), CGPoint(x: 540, y: 30), CGPoint(x: 540, y: 500), CGPoint(x: 30, y: 500)] }
    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        controls = EditorControlPreferences(defaults: defaults, palette: nil); controls.tools.selected = .lasso
        container = try PersistenceController.makeContainer(inMemory: true); Self.containers.append(container)
        let book = Notebook(title: "Lasso QA")
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
        try container.mainContext.save()
        session = EditorSession(notebook: book, context: container.mainContext, storage: DrawingStorage(root: root), handwriting: HandwritingAssistant(defaults: defaults))
    }
    func open() async throws {
        await session.open(page)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let view = UIHostingController(rootView: EditorView(session: session, onLibrary: {}, controls: controls, showsWorkspaceTabs: false))
        window.rootViewController = view; window.isHidden = false; view.view.frame = window.bounds; controller = view
        await settle()
        host = try XCTUnwrap(descendants(view.view).compactMap { $0 as? CanvasHost }.first)
        let points = [CGPoint(x: 60, y: 60), CGPoint(x: 160, y: 110)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        canvas.drawing = ink; session.changed(ink)
        var text = PageElement(kind: .text, rect: CGRect(x: 60, y: 130, width: 240, height: 50))
        text.text = "Converted handwriting"; text.fontName = HandwritingFont.defaultName; text.originalInk = ink.dataRepresentation()
        text.originalInkAnchorX = text.x; text.originalInkAnchorY = text.y
        let shape = PageElement(kind: .rectangle, rect: CGRect(x: 320, y: 80, width: 100, height: 80))
        var sticky = PageElement(kind: .text, rect: CGRect(x: 80, y: 230, width: 200, height: 120)); sticky.stickyStyle = .yellow; sticky.text = "A note"
        var tape = PageElement(kind: .tape, rect: CGRect(x: 320, y: 270, width: 100, height: 40)); tape.text = "Answer"
        XCTAssertTrue(session.replaceElements([text, shape, sticky, tape]))
        canvas.undoManager?.removeAllActions()
        await settle()
        XCTAssertTrue(overlay.active); XCTAssertTrue(session.canvas === canvas)
    }
    func waitForSelection() async throws { try await waitForIdle(); XCTAssertNotNil(overlay.selection) }
    func waitForIdle() async throws {
        for _ in 0..<200 { if !overlay.isTracking { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Lasso did not release input guard")
    }
    func settle() async { controller?.view.layoutIfNeeded(); try? await Task.sleep(for: .milliseconds(100)); controller?.view.layoutIfNeeded() }
    func cleanup() {
        host?.lasso.reset(); session.discardPreparedPages(); session.handwriting.cancel(); session.canvas?.undoManager?.removeAllActions()
        window?.isHidden = true; window?.rootViewController = nil; controller = nil
        defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

@MainActor private final class LassoTestPan: UIPanGestureRecognizer {
    var phase: UIGestureRecognizer.State = .possible
    var origin = CGPoint.zero
    var offset = CGPoint.zero
    override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
    override func location(in view: UIView?) -> CGPoint { CGPoint(x: origin.x + offset.x, y: origin.y + offset.y) }
    override func translation(in view: UIView?) -> CGPoint { offset }
}
