import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class FocusModeTests: XCTestCase {
    private var containers: [ModelContainer] = []

    func testFocusPreservesCanvasUndoPalettePreferencesAndNativeExitWorks() async throws {
        let name = "FocusMode.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let focus = EditorFocusMode(), palette = QuickPalettePreferences(defaults: defaults)
        palette.isVisible = false; palette.isCollapsed = true
        let placement = EditorToolbarPreferences(defaults: defaults); placement.position = .right
        let container = try PersistenceController.makeContainer(inMemory: true); containers.append(container)
        let notebook = Notebook(title: "Focus"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let points = [CGPoint(x: 80, y: 220), CGPoint(x: 280, y: 300)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        session.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue),
                                                      path: PKStrokePath(controlPoints: points, creationDate: .now))])
        let window = try window(size: CGSize(width: 1180, height: 820))
        let host = UIHostingController(rootView: EditorView(session: session, onLibrary: {}, toolbarPlacement: placement,
                                                          focusMode: focus, palette: palette))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let canvas = try XCTUnwrap(session.canvas)
        let ink = canvas.drawing
        var text = PageElement(kind: .text, rect: CGRect(x: 100, y: 100, width: 250, height: 100))
        text.text = "Stay focused"
        XCTAssertTrue(session.insertElement(text))
        let pageMenu = try XCTUnwrap(button("editor.pageOptions", in: host.view)?.menu)
        let enterFocus = try XCTUnwrap(actions(pageMenu).first { $0.title == "Focus Mode" })
        let trigger = UIButton(type: .system)
        trigger.addAction(enterFocus, for: .primaryActionTriggered)
        trigger.sendActions(for: .primaryActionTriggered)
        XCTAssertTrue(focus.isActive)
        try await settle(host)
        XCTAssertNil(button("editor.pageOptions", in: host.view))
        let exit = try XCTUnwrap(button("editor.exitFocusMode", in: host.view))
        XCTAssertTrue(exit.isEnabled); XCTAssertEqual(exit.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertTrue(session.canvas === canvas); XCTAssertEqual(canvas.drawing, ink)
        XCTAssertTrue(canvas.undoManager?.canUndo == true)
        XCTAssertFalse(palette.isVisible); XCTAssertTrue(palette.isCollapsed)
        capture(host, name: "Focus-Landscape")
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        host.view.frame = window.bounds
        try await settle(host)
        XCTAssertTrue(session.canvas === canvas)
        capture(host, name: "Focus-Portrait")
        try XCTUnwrap(button("editor.exitFocusMode", in: host.view)).sendActions(for: .primaryActionTriggered)
        try await settle(host)
        XCTAssertFalse(focus.isActive)
        XCTAssertNotNil(button("editor.pageOptions", in: host.view))
        XCTAssertTrue(session.canvas === canvas)
        XCTAssertEqual(placement.position, .right)
        XCTAssertFalse(palette.isVisible); XCTAssertTrue(palette.isCollapsed)
        canvas.undoManager?.undo(); XCTAssertTrue(session.elements.isEmpty)
        capture(host, name: "Focus-Exit-Restored")
        // Failed page loading must never hide the only way out of Focus Mode.
        focus.enter(); session.ready = false
        try await settle(host)
        let recoveryExit = try XCTUnwrap(button("editor.exitFocusMode", in: host.view))
        recoveryExit.sendActions(for: .primaryActionTriggered)
        XCTAssertFalse(focus.isActive)
    }

    func testNativeSidebarGesturePolicyRestoresItsOriginalValue() throws {
        let split = UISplitViewController(style: .doubleColumn), detail = UIViewController()
        split.setViewController(UIViewController(), for: .primary); split.setViewController(detail, for: .secondary)
        let window = try window(size: CGSize(width: 1180, height: 820))
        window.rootViewController = split; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        detail.loadViewIfNeeded()
        let probe = FocusSplitViewPolicy.Probe(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        split.view.addSubview(probe)
        split.presentsWithGesture = true
        probe.focusEnabled = true; probe.apply()
        XCTAssertFalse(split.presentsWithGesture)
        probe.focusEnabled = false; probe.apply()
        XCTAssertTrue(split.presentsWithGesture)
        split.presentsWithGesture = false
        probe.focusEnabled = true; probe.apply(); probe.restore()
        XCTAssertFalse(split.presentsWithGesture)
    }

    func testLibraryFocusHidesSidebarWithoutRecreatingEditor() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true); containers.append(container)
        let notebook = Notebook(title: "Library focus"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let name = "LibraryFocus.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let workspace = DocumentWorkspace(context: container.mainContext, defaults: defaults), focus = EditorFocusMode()
        await workspace.restore(); _ = await workspace.open(notebook)
        let window = try window(size: CGSize(width: 1366, height: 1024))
        let host = UIHostingController(rootView: LibraryView(context: container.mainContext, workspace: workspace, focusMode: focus)
            .modelContainer(container))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        try await settle(host)
        let canvas = try XCTUnwrap(workspace.activeSession?.canvas)
        focus.enter()
        try await settle(host)
        XCTAssertTrue(workspace.activeSession?.canvas === canvas)
        let split = try XCTUnwrap(controllers(host).compactMap { $0 as? UISplitViewController }.first)
        XCTAssertFalse(split.presentsWithGesture)
        XCTAssertNotNil(button("editor.exitFocusMode", in: host.view))
        XCTAssertNil(button("editor.pageOptions", in: host.view))
        capture(host, name: "Focus-Library-Sidebar-Hidden")
        focus.exit()
        try await settle(host)
        XCTAssertTrue(workspace.activeSession?.canvas === canvas)
        XCTAssertNotNil(button("editor.pageOptions", in: host.view))
    }

    private func window(size: CGSize) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size); return window
    }
    private func settle<Content: View>(_ host: UIHostingController<Content>) async throws {
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(150)); host.view.layoutIfNeeded()
    }
    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private func actions(_ menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { element in
            if let action = element as? UIAction { return [action] }
            if let submenu = element as? UIMenu { return actions(submenu) }
            return []
        }
    }
    private func controllers(_ controller: UIViewController) -> [UIViewController] {
        [controller] + controller.children.flatMap(controllers)
    }
    private func button(_ id: String, in view: UIView) -> UIButton? {
        descendants(view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == id }
    }
    private func capture<Content: View>(_ host: UIHostingController<Content>, name: String) {
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
