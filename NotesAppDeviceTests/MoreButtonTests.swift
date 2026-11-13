import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor private final class WritingGesture: UIGestureRecognizer {
    override var state: UIGestureRecognizer.State { get { .changed } set {} }
}
@MainActor private final class WritingCanvas: PKCanvasView {
    private let writing = WritingGesture()
    override var drawingGestureRecognizer: UIGestureRecognizer { writing }
}

@MainActor final class MoreButtonTests: XCTestCase {
    func testSingleActivationOpensRealQuickAdjustmentsPopoverAndWholeSquareIsTappable() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "More button"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let name = "MoreButton.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ToolPreferences(defaults: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 900)
        let host = UIHostingController(rootView: VStack {
            HStack {
                ToolbarQuickControls(preferences: preferences, session: session, inline: false, edit: { _ in })
            }.padding(4).modifier(EditorGlassCapsule())
            Spacer()
        }.padding(24))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let button = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "editor.quickAdjustments" })
        XCTAssertEqual(button.bounds.width, 44, accuracy: 0.1)
        XCTAssertEqual(button.bounds.height, 44, accuracy: 0.1)
        for point in [CGPoint(x: 2, y: 22), CGPoint(x: 42, y: 22), CGPoint(x: 22, y: 2), CGPoint(x: 22, y: 42)] {
            let hit = host.view.hitTest(button.convert(point, to: host.view), with: nil)
            XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true,
                          "Whitespace around the ellipsis must activate the button.")
        }
        button.sendActions(for: .primaryActionTriggered) // One activation, no retry loop.
        for _ in 0..<100 {
            if host.presentedViewController != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let presented = try XCTUnwrap(host.presentedViewController)
        XCTAssertEqual(presented.modalPresentationStyle, .popover)
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(button.window === window)
        host.dismiss(animated: false)
        // Retain the SwiftData container throughout the asynchronous presentation test.
        withExtendedLifetime(container) {}
    }

    func testNativeActivationUsesLatestActionAndHonorsDisabledState() {
        var first = 0, second = 0
        let coordinator = EditorMoreButton.Coordinator { first += 1 }
        let button = UIButton(type: .system)
        button.addTarget(coordinator, action: #selector(EditorMoreButton.Coordinator.activate(_:)), for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(first, 1)
        coordinator.action = { second += 1 }
        button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(first, 1); XCTAssertEqual(second, 1)
        button.isEnabled = false
        button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(second, 1)
    }

    func testTabStripMoreButtonReceivesTouchesWhileNavigationRemainsProtected() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Menu during writing"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let name = "TopMoreButton.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let workspace = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        await workspace.restore()
        let opened = await workspace.open(notebook); XCTAssertTrue(opened)
        let session = try XCTUnwrap(workspace.activeSession)
        session.canvas = WritingCanvas()
        XCTAssertTrue(workspace.blocksNavigation)
        XCTAssertFalse(workspace.blocksTabControls)
        let placement = EditorToolbarPreferences(defaults: defaults)
        let menu = EditorPageMenu(session: session, workspace: workspace,
                                  palette: QuickPalettePreferences(defaults: defaults),
                                  placement: placement, fingerDrawing: false,
                                  setFingerDrawing: { _ in }, present: { _ in }, share: { _ in }).make()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let host = UIHostingController(rootView: VStack {
            DocumentTabBar(workspace: workspace, showLibrary: {}, toggleSidebar: {}, showsRecents: false) {
                EditorMoreButton(title: "Page Options", identifier: "editor.pageOptions", menu: menu)
                    .frame(width: 44, height: 44)
            }
            Spacer()
        })
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let button = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "editor.pageOptions" })
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.showsMenuAsPrimaryAction)
        XCTAssertNotNil(button.menu)
        for point in [CGPoint(x: 2, y: 22), CGPoint(x: 42, y: 22), CGPoint(x: 22, y: 2), CGPoint(x: 22, y: 42)] {
            let hit = host.view.hitTest(button.convert(point, to: host.view), with: nil)
            XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true)
        }
        // Actual navigation still checks the live recognizer, rather than a rendered hit-test flag.
        let library = await workspace.showLibrary(); XCTAssertFalse(library)
        XCTAssertEqual(workspace.activeID, notebook.id)
        if #available(iOS 17.4, *) {
            button.performPrimaryAction()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Compact-Editor-Menu"; attachment.lifetime = .keepAlways
            add(attachment)
            button.contextMenuInteraction?.dismissMenu()
        }
        let groups = menu.children.compactMap { $0 as? UIMenu }.flatMap(\.children)
        let workspaceMenu = try XCTUnwrap(groups.compactMap { $0 as? UIMenu }.first { $0.title == "Workspace" })
        let positions = try XCTUnwrap(workspaceMenu.children.compactMap { $0 as? UIMenu }.first { $0.title == "Toolbar Position" })
        let right = try XCTUnwrap(positions.children.compactMap { $0 as? UIAction }.first { $0.title == "Right" })
        let actionButton = UIButton(type: .system)
        actionButton.addAction(right, for: .primaryActionTriggered)
        actionButton.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(placement.position, .right)
        withExtendedLifetime(container) {}
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
