import XCTest
import SwiftUI
import SwiftData
import PencilKit
import PDFKit
@testable import NotesApp

@MainActor final class SplitWorkspaceTests: XCTestCase {
    func testNativePanesKeepIndependentInkToolsUndoAndCanvasThroughFocusResizeSwapAndClose() async throws {
        let f = try SplitFixture(); defer { f.cleanup() }
        _ = await f.workspace.open(f.a); _ = await f.workspace.openBeside(f.b)
        let a = try XCTUnwrap(f.workspace.primarySession), b = try XCTUnwrap(f.workspace.secondarySession)
        let focus = EditorFocusMode(), window = try window(size: CGSize(width: 1180, height: 820))
        let host = UIHostingController(rootView: WorkspaceEditorView(workspace: f.workspace, focusMode: focus,
            showLibrary: {}, toggleSidebar: {}, preferencesDefaults: f.defaults))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; try await settle(host.view)
        let ac = try XCTUnwrap(a.canvas), bc = try XCTUnwrap(b.canvas)
        XCTAssertFalse(ac === bc)
        let aInk = ink(.blue), bInk = ink(.red)
        ac.drawing = aInk; bc.drawing = bInk
        ac.undoManager?.registerUndo(withTarget: ac) { $0.drawing = PKDrawing() }
        bc.undoManager?.registerUndo(withTarget: bc) { $0.drawing = PKDrawing() }
        let aContainer = try XCTUnwrap(descendants(host.view).compactMap { $0 as? PageCanvasContainer }.first { $0.current?.ink === ac })
        let bContainer = try XCTUnwrap(descendants(host.view).compactMap { $0 as? PageCanvasContainer }.first { $0.current?.ink === bc })
        let aPencil = try pencil(in: aContainer), bPencil = try pencil(in: bContainer)
        f.workspace.focus(f.a.id)
        bContainer.paneTouchObserver.touchesBegan([], with: UIEvent())
        XCTAssertEqual(f.workspace.activeID, f.b.id)
        XCTAssertFalse(bContainer.paneTouchObserver.cancelsTouchesInView)
        XCTAssertFalse(bContainer.paneTouchObserver.canPrevent(bc.drawingGestureRecognizer))
        bPencil.receiveTap(.switchEraser); try await settle(host.view)
        XCTAssertTrue(bc.tool is PKEraserTool); XCTAssertTrue(ac.tool is PKInkingTool)
        aPencil.receiveTap(.switchEraser); try await settle(host.view)
        XCTAssertTrue(ac.tool is PKInkingTool) // Inactive pane does not handle the same hardware callback.
        aContainer.onInteraction?(); try await settle(host.view)
        XCTAssertEqual(f.workspace.activeID, f.a.id)
        aPencil.receiveTap(.switchEraser); try await settle(host.view)
        XCTAssertTrue(ac.tool is PKEraserTool); XCTAssertTrue(bc.tool is PKEraserTool)
        capture(window, name: "Two-Documents-Landscape")
        f.workspace.setSplitFraction(0.6)
        f.workspace.swapPanes(); try await settle(host.view)
        XCTAssertTrue(a.canvas === ac && b.canvas === bc)
        XCTAssertEqual(f.workspace.visibleSessions.map { $0.notebook.id }, [f.b.id, f.a.id])
        window.frame = CGRect(x: 0, y: 0, width: 540, height: 820); host.view.frame = window.bounds
        try await settle(host.view)
        XCTAssertTrue(a.canvas === ac && b.canvas === bc)
        capture(window, name: "Two-Documents-Narrow-Stacked")
        f.workspace.focus(f.b.id); focus.enter(documentID: f.b.id)
        try await settle(host.view)
        XCTAssertTrue(a.canvas === ac && b.canvas === bc)
        XCTAssertEqual(bc.drawing, bInk)
        capture(window, name: "Two-Documents-Focus")
        focus.exit(); try await settle(host.view)
        let joined = await f.workspace.closeSplit(); XCTAssertTrue(joined)
        try await settle(host.view)
        XCTAssertFalse(f.workspace.isSplit); XCTAssertTrue(f.workspace.activeSession === b)
        XCTAssertTrue(b.canvas === bc); XCTAssertTrue(bc.undoManager?.canUndo == true)
        XCTAssertEqual(bc.drawing, bInk); XCTAssertTrue(f.workspace.openNotebooks.contains { $0.id == f.a.id })
        let savedA = try await f.storage.read(try XCTUnwrap(a.page?.drawingFilePath))
        let savedB = try await f.storage.read(try XCTUnwrap(b.page?.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: savedA), aInk); XCTAssertEqual(try PKDrawing(data: savedB), bInk)
    }

    func testDualSessionRestorationAndLegacyTabsKeepPermanentPageMemories() async throws {
        let f = try SplitFixture(); defer { f.cleanup() }
        let legacy: [String: Any] = ["openIDs": [f.a.id.uuidString], "recentIDs": [f.a.id.uuidString],
                                  "activeID": f.a.id.uuidString, "pages": [f.a.id.uuidString, f.a.orderedPages[1].id.uuidString]]
        f.defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "workspace.tabs.v1")
        let legacyWorkspace = DocumentWorkspace(context: f.container.mainContext, storage: f.storage, defaults: f.defaults)
        await legacyWorkspace.restore()
        XCTAssertEqual(legacyWorkspace.activeSession?.page?.id, f.a.orderedPages[1].id)
        XCTAssertFalse(legacyWorkspace.isSplit)
        _ = await legacyWorkspace.openBeside(f.b)
        let right = try XCTUnwrap(legacyWorkspace.secondarySession)
        await right.open(f.b.orderedPages[1]); legacyWorkspace.rememberCurrentPage()
        legacyWorkspace.focus(f.a.id); legacyWorkspace.setSplitFraction(0.6); legacyWorkspace.swapPanes()
        let restored = DocumentWorkspace(context: f.container.mainContext, storage: f.storage, defaults: f.defaults)
        await restored.restore()
        XCTAssertTrue(restored.isSplit); XCTAssertEqual(restored.activeID, f.a.id)
        XCTAssertEqual(restored.primarySession?.page?.id, f.a.orderedPages[1].id)
        XCTAssertEqual(restored.secondarySession?.page?.id, f.b.orderedPages[1].id)
        XCTAssertEqual(restored.visibleSessions.map { $0.notebook.id }, [f.b.id, f.a.id])
        XCTAssertEqual(restored.splitFraction, 0.4, accuracy: 0.001)
        f.b.trashedAt = .now; try f.container.mainContext.save()
        let pruned = DocumentWorkspace(context: f.container.mainContext, storage: f.storage, defaults: f.defaults)
        await pruned.restore()
        XCTAssertFalse(pruned.isSplit); XCTAssertEqual(pruned.activeID, f.a.id)
        XCTAssertFalse(pruned.openNotebooks.contains { $0.id == f.b.id })
        legacyWorkspace.discardPreparedPages(); restored.discardPreparedPages(); pruned.discardPreparedPages()
    }

    func testSplitFocusRestoresOneSidebarGesturePolicyWithoutReplacingEitherCanvas() async throws {
        let f = try SplitFixture(); defer { f.cleanup() }
        await f.workspace.restore()
        _ = await f.workspace.open(f.a); _ = await f.workspace.openBeside(f.b)
        let focus = EditorFocusMode(), window = try window(size: CGSize(width: 1366, height: 1024))
        let host = UIHostingController(rootView: LibraryView(context: f.container.mainContext, workspace: f.workspace,
            focusMode: focus).modelContainer(f.container))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; try await settle(host.view)
        func controllers(_ controller: UIViewController) -> [UIViewController] {
            [controller] + controller.children.flatMap(controllers)
        }
        let split = try XCTUnwrap(controllers(host).compactMap { $0 as? UISplitViewController }.first)
        split.presentsWithGesture = true
        let a = try XCTUnwrap(f.workspace.primarySession?.canvas), b = try XCTUnwrap(f.workspace.secondarySession?.canvas)
        focus.enter(documentID: f.b.id); try await settle(host.view)
        XCTAssertFalse(split.presentsWithGesture)
        focus.exit(); try await settle(host.view)
        XCTAssertTrue(split.presentsWithGesture)
        XCTAssertTrue(f.workspace.primarySession?.canvas === a && f.workspace.secondarySession?.canvas === b)
    }

    func testFailedSaveKeepsBothPanesAndPendingInkForEveryDestructiveNavigationBoundary() async throws {
        let f = try SplitFixture(blockedStorage: true); defer { f.cleanup() }
        _ = await f.workspace.open(f.a); _ = await f.workspace.openBeside(f.b)
        let a = try XCTUnwrap(f.workspace.primarySession), b = try XCTUnwrap(f.workspace.secondarySession)
        a.changed(ink(.blue)); b.changed(ink(.red))
        let replace = await f.workspace.open(f.c)
        let beside = await f.workspace.openBeside(f.c)
        let single = await f.workspace.closeSplit()
        let close = await f.workspace.close(f.a.id)
        let forget = await f.workspace.forget(Set([f.a.id, f.b.id]))
        let library = await f.workspace.showLibrary()
        XCTAssertFalse(replace || beside || single || close || forget || library)
        XCTAssertTrue(f.workspace.primarySession === a && f.workspace.secondarySession === b)
        XCTAssertEqual(f.workspace.openNotebooks.map(\.id), [f.a.id, f.b.id])
        XCTAssertTrue(a.hasPendingSave && b.hasPendingSave)
        XCTAssertEqual(a.drawing.strokes.count, 1); XCTAssertEqual(b.drawing.strokes.count, 1)
        XCTAssertNotNil(a.errorMessage); XCTAssertNotNil(b.errorMessage)
    }

    func testDuplicateAliasedMissingAndTrashedDocumentsAreRejectedWithoutReplacingPanes() async throws {
        let f = try SplitFixture(); defer { f.cleanup() }
        _ = await f.workspace.open(f.a)
        let same = await f.workspace.openBeside(f.a); XCTAssertFalse(same)
        f.a.orderedPages[0].drawingFilePath = "shared/ink.drawing"
        f.b.orderedPages[0].drawingFilePath = "shared//./ink.drawing"
        let alias = await f.workspace.openBeside(f.b); XCTAssertFalse(alias)
        XCTAssertFalse(f.workspace.isSplit)
        f.b.orderedPages[0].drawingFilePath = nil
        let opened = await f.workspace.openBeside(f.b); XCTAssertTrue(opened)
        let a = f.workspace.primarySession, b = f.workspace.secondarySession
        f.c.trashedAt = .now
        let trashed = await f.workspace.openBeside(f.c); XCTAssertFalse(trashed)
        let missing = await f.workspace.open(f.a, pageID: UUID()); XCTAssertFalse(missing)
        XCTAssertTrue(f.workspace.primarySession === a && f.workspace.secondarySession === b)
        let focusedExisting = await f.workspace.open(f.a)
        XCTAssertTrue(focusedExisting); XCTAssertTrue(f.workspace.activeSession === a)
        XCTAssertEqual(f.workspace.visibleSessions.count, 2)
        f.workspace.setSplitFraction(.nan); XCTAssertEqual(f.workspace.splitFraction, 0.5)
        f.workspace.setSplitFraction(2); XCTAssertEqual(f.workspace.splitFraction, 0.7)
    }

    func testBackgroundSaveAndPageChangesKeepPDFAndNoteIndependent() async throws {
        let f = try SplitFixture(); defer { f.cleanup() }
        let sourceURL = f.root.appendingPathComponent("source.pdf")
        let original = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 200)).pdfData { renderer in
            renderer.beginPage(); ("Original PDF" as NSString).draw(at: CGPoint(x: 20, y: 20))
        }
        try original.write(to: sourceURL)
        let library = LibraryViewModel(context: f.container.mainContext, storage: f.storage)
        let imported = await library.importPDF(from: sourceURL, folder: nil); XCTAssertTrue(imported)
        let pdf = try XCTUnwrap(library.notebooks.first { $0.pages.first?.pdfFilePath != nil })
        _ = await f.workspace.open(f.a); _ = await f.workspace.openBeside(pdf)
        let noteSession = try XCTUnwrap(f.workspace.primarySession), pdfSession = try XCTUnwrap(f.workspace.secondarySession)
        XCTAssertNotNil(pdfSession.pdfBackground)
        noteSession.changed(ink(.blue)); pdfSession.changed(ink(.red))
        let pdfPageID = pdfSession.page?.id
        await noteSession.open(f.a.orderedPages[1])
        XCTAssertEqual(pdfSession.page?.id, pdfPageID); XCTAssertEqual(pdfSession.drawing.strokes.count, 1)
        f.workspace.backgroundSave()
        for _ in 0..<100 {
            if !pdfSession.hasPendingSave, pdfSession.page?.drawingFilePath != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let savedNote = try await f.storage.read(try XCTUnwrap(f.a.orderedPages[0].drawingFilePath))
        let savedPDF = try await f.storage.read(try XCTUnwrap(pdfSession.page?.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: savedNote).strokes.count, 1)
        XCTAssertEqual(try PKDrawing(data: savedPDF).strokes.count, 1)
        let result = await pdfSession.export(currentPageOnly: true)
        let exported = try XCTUnwrap(result)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: exported))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 300, height: 200))
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        let privateSource = try await f.storage.read(try XCTUnwrap(pdf.pages.first?.pdfFilePath))
        XCTAssertEqual(privateSource, original)
    }

    private func pencil(in view: UIView) throws -> PencilDoubleTapCoordinator {
        let interaction = try XCTUnwrap(view.interactions.compactMap { $0 as? UIPencilInteraction }.first)
        return try XCTUnwrap(interaction.delegate as? PencilDoubleTapCoordinator)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func window(size: CGSize) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size); return window
    }
    private func settle(_ view: UIView) async throws {
        view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(180)); view.layoutIfNeeded()
    }
    private func capture(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func ink(_ color: UIColor) -> PKDrawing {
        let points = [CGPoint(x: 40, y: 120), CGPoint(x: 280, y: 230)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: 5, height: 5),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }
}

@MainActor private final class SplitFixture {
    let container: ModelContainer
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "SplitWorkspace.\(UUID())"
    let defaults: UserDefaults
    let storage: DrawingStorage
    let workspace: DocumentWorkspace
    let a = Notebook(title: "Biology notes"), b = Notebook(title: "Practice notebook"), c = Notebook(title: "Third document")
    init(blockedStorage: Bool = false) throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binaryRoot = root.appendingPathComponent("documents")
        if blockedStorage { try Data([0]).write(to: binaryRoot) }
        storage = DrawingStorage(root: binaryRoot)
        workspace = DocumentWorkspace(context: container.mainContext, storage: storage, defaults: defaults)
        for book in [a, b, c] {
            container.mainContext.insert(book)
            for index in 0..<2 {
                let page = NotePage(pageIndex: index); container.mainContext.insert(page); book.pages.append(page)
            }
        }
        try container.mainContext.save()
    }
    func cleanup() {
        workspace.discardPreparedPages(); defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
