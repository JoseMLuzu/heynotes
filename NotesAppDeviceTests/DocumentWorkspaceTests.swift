import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class DocumentWorkspaceTests: XCTestCase {
    func testUnchangedPageMemoriesAvoidDefaultsWritesButRealNavigationPersists() async throws {
        let suite = "WorkspaceNoOps.\(UUID())"
        let defaults = try XCTUnwrap(FluidityDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = makeNotebook("Navigation", context: container.mainContext)
        let workspace = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        await workspace.restore()
        _ = await workspace.open(notebook)
        let writes = defaults.dataWrites
        for _ in 0..<50 { workspace.rememberCurrentPage() }
        XCTAssertEqual(defaults.dataWrites, writes)
        let secondPage = notebook.orderedPages[1]
        await workspace.activeSession?.open(secondPage)
        workspace.rememberCurrentPage()
        XCTAssertEqual(defaults.dataWrites, writes + 1)
        for _ in 0..<50 { workspace.rememberCurrentPage() }
        XCTAssertEqual(defaults.dataWrites, writes + 1)
        let reopened = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        await reopened.restore()
        XCTAssertEqual(reopened.activeID, notebook.id)
        XCTAssertEqual(reopened.activeSession?.page?.id, secondPage.id)
        XCTAssertEqual(defaults.dataWrites, writes + 1)
        withExtendedLifetime(container) {}
    }

    private func makeNotebook(_ title: String, context: ModelContext) -> Notebook {
        let notebook = Notebook(title: title)
        context.insert(notebook)
        for index in 0..<2 {
            let page = NotePage(pageIndex: index)
            context.insert(page); notebook.pages.append(page)
        }
        return notebook
    }

    private func ink() -> PKDrawing {
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 80)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }

    func testSwitchingFlushesNativeInkPreservesPageAndClosingDoesNotDelete() async throws {
        let suite = "WorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = makeNotebook("Anatomy", context: context), b = makeNotebook("Biology", context: context)
        try context.save()
        let storage = DrawingStorage(root: root)
        let workspace = DocumentWorkspace(context: context, storage: storage, defaults: defaults)
        await workspace.restore()
        let opened = await workspace.open(a)
        XCTAssertTrue(opened)
        let original = try XCTUnwrap(workspace.activeSession)
        let secondPage = a.orderedPages[1]
        await original.open(secondPage)
        let canvas = InkCanvas(); canvas.pageID = secondPage.id; canvas.drawing = ink()
        original.canvas = canvas // No delegate notification: switching must capture native ink directly.
        let switched = await workspace.open(b)
        XCTAssertTrue(switched)
        XCTAssertNil(original.canvas)
        XCTAssertEqual(workspace.openNotebooks.map(\.id), [a.id, b.id])
        let bytes = try await storage.read(try XCTUnwrap(secondPage.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: bytes).strokes.count, 1)
        _ = await workspace.open(a)
        XCTAssertEqual(workspace.activeSession?.page?.id, secondPage.id)
        XCTAssertEqual(workspace.activeSession?.drawing.strokes.count, 1)
        _ = await workspace.open(a)
        XCTAssertEqual(workspace.openNotebooks.count, 2)
        _ = await workspace.close(b.id)
        XCTAssertEqual(workspace.activeID, a.id)
        _ = await workspace.open(b)
        _ = await workspace.showLibrary()
        XCTAssertNil(workspace.activeSession)
        XCTAssertEqual(workspace.openNotebooks.count, 2)
        _ = await workspace.open(a)
        _ = await workspace.close(a.id)
        XCTAssertEqual(workspace.activeID, b.id)
        _ = await workspace.close(b.id)
        XCTAssertNil(workspace.activeID)
        XCTAssertTrue(workspace.openNotebooks.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Notebook>()), 2)
        XCTAssertTrue(workspace.recentNotebooks.contains { $0.id == a.id })
        _ = await workspace.open(a)
        XCTAssertEqual(workspace.activeSession?.page?.id, secondPage.id)
    }

    func testSwitchingVisibleTabsKeepsToolbarAndScrollPosition() async throws {
        let suite = "TabLayout.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let notebooks = (1...9).map { makeNotebook("Notebook \($0)", context: context) }
        let target = notebooks[2]
        for index in 2..<104 {
            let page = NotePage(pageIndex: index)
            context.insert(page)
            target.pages.append(page)
        }

        let workspace = DocumentWorkspace(context: context, defaults: defaults)
        await workspace.restore()
        for notebook in notebooks { _ = await workspace.open(notebook) }
        _ = await workspace.open(target)
        let lastPage = try XCTUnwrap(target.orderedPages.last)
        await workspace.activeSession?.open(lastPage)
        _ = await workspace.open(notebooks[0])

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 720)
        let host = UIHostingController(rootView: LibraryView(context: context, workspace: workspace).modelContainer(container))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(240))

        func descendants(of view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        func button(_ id: String) -> UIButton? {
            descendants(of: host.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == id }
        }
        func tabScrollView() -> UIScrollView? {
            descendants(of: host.view).compactMap { $0 as? UIScrollView }.first {
                abs($0.bounds.height - 44) < 1 && $0.contentSize.width > $0.bounds.width + 100
            }
        }
        let pageOptions = try XCTUnwrap(button("editor.pageOptions"))
        let quickAdjustments = try XCTUnwrap(button("editor.quickAdjustments"))
        let tabs = try XCTUnwrap(tabScrollView())
        let outgoingCanvas = try XCTUnwrap(workspace.activeSession?.canvas)
        tabs.setContentOffset(CGPoint(x: 120, y: tabs.contentOffset.y), animated: false)
        let oldOffset = tabs.contentOffset.x
        let oldOptionsFrame = pageOptions.convert(pageOptions.bounds, to: window)
        let oldAdjustmentsFrame = quickAdjustments.convert(quickAdjustments.bounds, to: window)

        let opened = await workspace.open(target)
        XCTAssertTrue(opened)
        try await Task.sleep(for: .milliseconds(240))
        XCTAssertEqual(workspace.activeSession?.page?.id, lastPage.id)
        let incomingCanvas = try XCTUnwrap(workspace.activeSession?.canvas)
        XCTAssertFalse(incomingCanvas === outgoingCanvas)
        XCTAssertTrue(button("editor.pageOptions") === pageOptions)
        XCTAssertTrue(button("editor.quickAdjustments") === quickAdjustments)
        XCTAssertEqual(pageOptions.convert(pageOptions.bounds, to: window), oldOptionsFrame)
        XCTAssertEqual(quickAdjustments.convert(quickAdjustments.bounds, to: window), oldAdjustmentsFrame)
        XCTAssertTrue(tabScrollView() === tabs)
        XCTAssertEqual(tabs.contentOffset.x, oldOffset, accuracy: 0.5)

        let distantNotebook = try XCTUnwrap(notebooks.last)
        let openedDistant = await workspace.open(distantNotebook)
        XCTAssertTrue(openedDistant)
        try await Task.sleep(for: .milliseconds(240))
        XCTAssertTrue(tabScrollView() === tabs)
        XCTAssertGreaterThan(tabs.contentOffset.x, oldOffset)
        XCTAssertTrue(button("editor.pageOptions") === pageOptions)
        withExtendedLifetime(container) {}
    }

    func testRestoreTabsActivePageAndPruneDeletedNotebooks() async throws {
        let suite = "WorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = makeNotebook("A", context: context), b = makeNotebook("B", context: context)
        try context.save()
        let workspace = DocumentWorkspace(context: context, defaults: defaults)
        await workspace.restore()
        _ = await workspace.open(a); _ = await workspace.open(b)
        let bookmark = b.orderedPages[1].id
        await workspace.activeSession?.open(b.orderedPages[1])
        workspace.rememberCurrentPage()
        let reopened = DocumentWorkspace(context: context, defaults: defaults)
        await reopened.restore()
        XCTAssertEqual(reopened.openNotebooks.map(\.id), [a.id, b.id])
        XCTAssertEqual(reopened.activeID, b.id)
        XCTAssertEqual(reopened.activeSession?.page?.id, bookmark)
        _ = await reopened.showLibrary()
        context.delete(a)
        try context.save()
        let pruned = DocumentWorkspace(context: context, defaults: defaults)
        await pruned.restore()
        XCTAssertNil(pruned.activeID)
        XCTAssertEqual(pruned.openNotebooks.map(\.id), [b.id])
        XCTAssertFalse(pruned.recentNotebooks.contains { $0.id == a.id })
        let forgotten = await pruned.forget(b.id)
        XCTAssertTrue(forgotten)
        XCTAssertTrue(pruned.openNotebooks.isEmpty)
        XCTAssertTrue(pruned.recentNotebooks.isEmpty)
    }

    func testWriteFailureBlocksSwitchCloseAndReturnToLibrary() async throws {
        let suite = "WorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: root) // Deliberately unusable document directory.
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = makeNotebook("A", context: context), b = makeNotebook("B", context: context)
        let workspace = DocumentWorkspace(context: context, storage: DrawingStorage(root: root), defaults: defaults)
        await workspace.restore()
        _ = await workspace.open(a)
        let session = try XCTUnwrap(workspace.activeSession)
        session.changed(ink())
        let switched = await workspace.open(b)
        let closed = await workspace.close(a.id)
        let returned = await workspace.showLibrary()
        XCTAssertFalse(switched); XCTAssertFalse(closed); XCTAssertFalse(returned)
        XCTAssertEqual(workspace.activeID, a.id)
        XCTAssertEqual(workspace.openNotebooks.map(\.id), [a.id])
        XCTAssertTrue(workspace.activeSession === session)
        XCTAssertEqual(session.drawing.strokes.count, 1)
        XCTAssertNotNil(session.errorMessage)
    }

    func testDeletedPageBookmarkFallsBackToExistingPage() async throws {
        let suite = "WorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = makeNotebook("A", context: container.mainContext)
        let workspace = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        await workspace.restore(); _ = await workspace.open(notebook)
        let second = notebook.orderedPages[1]
        await workspace.activeSession?.open(second)
        _ = await workspace.showLibrary()
        notebook.pages.removeAll { $0.id == second.id }
        container.mainContext.delete(second)
        try container.mainContext.save()
        let restored = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        await restored.restore(); _ = await restored.open(notebook)
        XCTAssertEqual(restored.activeSession?.page?.id, notebook.orderedPages.first?.id)
    }
}
