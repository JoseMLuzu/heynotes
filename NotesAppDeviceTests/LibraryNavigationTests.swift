import XCTest
import SwiftUI
import SwiftData
@testable import NotesApp

@MainActor final class LibraryNavigationTests: XCTestCase {
    func testFolderBackClimbsToParentAndLibraryWithAndWithoutOpenTabs() async throws {
        for hasTabs in [false, true] {
            let container = try PersistenceController.makeContainer(inMemory: true)
            let context = container.mainContext
            let parent = Folder(title: "University")
            let child = Folder(title: "Biology", parent: parent)
            let notebook = Notebook(title: "Open lecture")
            let page = NotePage(pageIndex: 0)
            context.insert(parent); context.insert(child); context.insert(notebook); context.insert(page)
            notebook.pages = [page]
            try context.save()
            let suite = "LibraryBack.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let workspace = DocumentWorkspace(context: context, defaults: defaults)
            let navigation = LibraryNavigation()
            await workspace.restore()
            if hasTabs {
                _ = await workspace.open(notebook)
                _ = await workspace.showLibrary()
            }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
            let host = UIHostingController(rootView: LibraryView(context: context, workspace: workspace, navigation: navigation)
                .modelContainer(container).modifier(AppAppearance()))
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.frame = window.bounds
            try await settle(host.view)

            navigation.open(parent)
            try await settle(host.view)
            let firstBack = try XCTUnwrap(backButton(in: host.view))
            XCTAssertTrue(firstBack.isEnabled)
            XCTAssertEqual(firstBack.accessibilityLabel, "Back to Library")

            navigation.open(child)
            try await settle(host.view)
            let childBack = try XCTUnwrap(backButton(in: host.view))
            XCTAssertEqual(childBack.accessibilityLabel, "Back to University")
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = hasTabs ? "Folder-Back-With-Tabs" : "Folder-Back-Without-Tabs"
            attachment.lifetime = .keepAlways
            add(attachment)
            childBack.sendActions(for: .primaryActionTriggered)
            try await settle(host.view)
            XCTAssertEqual(navigation.selection, .folder(parent.id))
            let parentBack = try XCTUnwrap(backButton(in: host.view))
            XCTAssertEqual(parentBack.accessibilityLabel, "Back to Library")
            parentBack.sendActions(for: .primaryActionTriggered)
            try await settle(host.view)
            XCTAssertEqual(navigation.selection, .library)
            if hasTabs { XCTAssertFalse(try XCTUnwrap(backButton(in: host.view)).isEnabled) }
            else { XCTAssertNil(backButton(in: host.view)) }
            XCTAssertNil(workspace.activeSession)
            XCTAssertEqual(workspace.openNotebooks.map(\.id), hasTabs ? [notebook.id] : [])
            withExtendedLifetime(container) {}
        }
    }

    private func settle(_ view: UIView) async throws {
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        view.layoutIfNeeded()
    }

    private func backButton(in view: UIView) -> UIButton? {
        ([view] + view.subviews.flatMap(descendants)).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "library.back" }
    }
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
