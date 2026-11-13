import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class NotebookPagesPanelTests: XCTestCase {
    func testDroppedReferencesReorderPersistAndKeepNewestInkAndPermanentLinks() async throws {
        let fixture = try await PagesFixture()
        defer { fixture.cleanup() }
        let session = fixture.session, pages = fixture.pages
        let paths = pages.map(\.drawingFilePath), ids = Set(pages.map(\.id))
        let canvas = InkCanvas(); canvas.pageID = pages[1].id; canvas.drawing = fixture.ink
        session.canvas = canvas; session.changed(fixture.ink)
        var text = PageElement(kind: .text, rect: CGRect(x: 40, y: 100, width: 160, height: 60))
        text.text = "Keep my undo history"
        XCTAssertTrue(session.insertElement(text))
        let source = NotebookPageDrag(notebookID: fixture.notebook.id, pageID: pages[1].id)
        let provider = NSItemProvider(); provider.register(source)
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("com.local.notesapp.page-reference"))
        let decoded: NotebookPageDrag = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: NotebookPageDrag.self) { continuation.resume(with: $0) }
        }
        XCTAssertEqual(decoded, source)
        XCTAssertTrue(session.reorderPage(decoded, onto: pages[3].id))
        XCTAssertEqual(fixture.notebook.orderedPages.map(\.id), [pages[0].id, pages[2].id, pages[3].id, pages[1].id])
        XCTAssertEqual(fixture.notebook.orderedPages.map(\.pageIndex), [0, 1, 2, 3])
        XCTAssertEqual(pages[1].section?.id, pages[3].section?.id)
        XCTAssertTrue(session.canvas === canvas); XCTAssertEqual(session.page?.id, pages[1].id)
        XCTAssertEqual(canvas.drawing, fixture.ink); XCTAssertTrue(canvas.undoManager?.canUndo == true)
        XCTAssertTrue(session.hasPendingSave)
        XCTAssertEqual(pages[1].bookmarkTitle, "Lecture bookmark")
        XCTAssertEqual(Set(pages.map(\.id)), ids); XCTAssertEqual(pages.map(\.drawingFilePath), paths)
        // A separate context reads the saved order rather than the original live objects.
        let readContext = ModelContext(fixture.store)
        let persisted = try XCTUnwrap(readContext.fetch(FetchDescriptor<Notebook>()).first)
        XCTAssertEqual(persisted.orderedPages.map(\.id), fixture.notebook.orderedPages.map(\.id))
        XCTAssertTrue(session.reorderPage(NotebookPageDrag(notebookID: fixture.notebook.id, pageID: pages[3].id), onto: pages[0].id))
        XCTAssertEqual(fixture.notebook.orderedPages.map(\.id), [pages[3].id, pages[0].id, pages[2].id, pages[1].id])
        XCTAssertEqual(pages[3].section?.id, pages[0].section?.id)
        let saved = await session.flush(); XCTAssertTrue(saved)
        let disk = try await fixture.storage.read(try XCTUnwrap(pages[1].drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: disk), fixture.ink)
        let untouched = try await fixture.storage.read(try XCTUnwrap(pages[2].drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: untouched).strokes.count, 0)
    }

    func testInvalidBusyMissingAndSelfDropsNeverChangeOrder() async throws {
        let fixture = try await PagesFixture()
        defer { fixture.cleanup() }
        let session = fixture.session, before = fixture.notebook.orderedPages.map(\.id)
        let valid = NotebookPageDrag(notebookID: fixture.notebook.id, pageID: fixture.pages[0].id)
        XCTAssertFalse(session.reorderPage(NotebookPageDrag(notebookID: UUID(), pageID: valid.pageID), onto: fixture.pages[1].id))
        XCTAssertFalse(session.reorderPage(NotebookPageDrag(notebookID: valid.notebookID, pageID: UUID()), onto: fixture.pages[1].id))
        XCTAssertFalse(session.reorderPage(valid, onto: UUID()))
        XCTAssertFalse(session.reorderPage(valid, onto: valid.pageID))
        session.busy = true
        XCTAssertFalse(session.reorderPage(valid, onto: fixture.pages[1].id))
        session.busy = false; session.ready = false
        XCTAssertFalse(session.reorderPage(valid, onto: fixture.pages[1].id))
        XCTAssertEqual(fixture.notebook.orderedPages.map(\.id), before)
    }

    func testFixedPopoverRegistersThumbnailDragsAndPreservesLiveCanvasDuringReordering() async throws {
        let fixture = try await PagesFixture()
        defer { fixture.cleanup() }
        let session = fixture.session, state = PanelTestState()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(rootView: PanelTestHarness(session: session, state: state))
        window.rootViewController = host; window.isHidden = false
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        try await settle(host.view)
        let canvas = try XCTUnwrap(session.canvas)
        let trigger = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "test.pages" })
        trigger.sendActions(for: .primaryActionTriggered)
        try await settle(host.view)
        let presented = try XCTUnwrap(host.presentedViewController)
        XCTAssertEqual(presented.modalPresentationStyle, .popover)
        XCTAssertNotNil(presented.popoverPresentationController?.sourceView)
        XCTAssertFalse(descendants(presented.view).contains { $0.accessibilityLabel == "Move Pages Panel" })
        XCTAssertTrue(descendants(presented.view).contains { $0.interactions.contains { $0 is UIDragInteraction } })
        XCTAssertTrue(descendants(presented.view).contains { $0.interactions.contains { $0 is UIDropInteraction } })
        let frame = presented.view.frame
        XCTAssertTrue(session.reorderPage(NotebookPageDrag(notebookID: fixture.notebook.id, pageID: fixture.pages[1].id), onto: fixture.pages[3].id))
        try await settle(host.view)
        XCTAssertEqual(presented.view.frame, frame)
        XCTAssertTrue(session.canvas === canvas)
        XCTAssertEqual(session.page?.id, fixture.pages[1].id)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Fixed-Pages-Reordering"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func settle(_ view: UIView) async throws {
        view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(250)); view.layoutIfNeeded()
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

@MainActor private final class PanelTestState: ObservableObject {
    @Published var visible = false
}
@MainActor private struct PanelTestHarness: View {
    let session: EditorSession
    @ObservedObject var state: PanelTestState
    var body: some View {
        VStack {
            HStack {
                Spacer()
                EditorMoreButton(title: "Show Pages", identifier: "test.pages", symbol: "square.grid.2x2") { state.visible.toggle() }
                    .frame(width: 44, height: 44)
                    .popover(isPresented: $state.visible) { NotebookPagesPanel(session: session) { state.visible = false } }
            }
            PaperCanvas(session: session, tool: PKInkingTool(.pen), fingerDrawing: false)
        }
    }
}

@MainActor private final class PagesFixture {
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store: ModelContainer
    let storage: DrawingStorage
    let notebook = Notebook(title: "Biology")
    let pages = (0..<4).map { NotePage(pageIndex: $0, paperTemplate: .grid) }
    let session: EditorSession
    let ink: PKDrawing
    init() async throws {
        store = try PersistenceController.makeContainer(inMemory: true)
        storage = DrawingStorage(root: root)
        let points = [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 90)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        store.mainContext.insert(notebook)
        let first = NotebookSection(title: "Introduction", sortIndex: 0), second = NotebookSection(title: "Cells", sortIndex: 1)
        store.mainContext.insert(first); store.mainContext.insert(second); notebook.sections = [first, second]
        for (index, page) in pages.enumerated() {
            store.mainContext.insert(page); page.section = index < 2 ? first : second
            let path = DrawingStorage.path(notebook: notebook.id, page: page.id)
            try await storage.write(PKDrawing().dataRepresentation(), to: path)
            page.drawingFilePath = path
        }
        notebook.pages = pages; pages[1].bookmarkTitle = "Lecture bookmark"
        try store.mainContext.save()
        session = EditorSession(notebook: notebook, context: store.mainContext, storage: storage)
        await session.open(pages[1])
    }
    func cleanup() { session.discardPreparedPages(); try? FileManager.default.removeItem(at: root) }
}
