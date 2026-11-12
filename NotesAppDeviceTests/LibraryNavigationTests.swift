import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class LibraryNavigationTests: XCTestCase {
    func testRestoringAnOpenEditorWithLibrarySortingRemainsResponsive() async throws {
        let defaults = UserDefaults.standard
        let previousSort = defaults.object(forKey: "library.sortOrder")
        defer {
            if let previousSort { defaults.set(previousSort, forKey: "library.sortOrder") }
            else { defaults.removeObject(forKey: "library.sortOrder") }
        }
        defaults.set("type", forKey: "library.sortOrder")
        _ = QuickPalettePreferences() // Finish any one-time migration before mounting the view.
        let paletteData = defaults.data(forKey: "editor.quickPalette.v2")
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Restored lecture")
        let page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page)
        notebook.pages = [page]
        let path = DrawingStorage.path(notebook: notebook.id, page: page.id)
        let ink = PKDrawing().dataRepresentation()
        try await storage.write(ink, to: path)
        page.drawingFilePath = path
        try container.mainContext.save()
        let suite = "LibraryLaunch.\(UUID())"
        let tabDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { tabDefaults.removePersistentDomain(forName: suite) }
        let saved = DocumentWorkspace(context: container.mainContext, storage: storage, defaults: tabDefaults)
        let opened = await saved.open(notebook)
        XCTAssertTrue(opened)
        let restored = DocumentWorkspace(context: container.mainContext, storage: storage, defaults: tabDefaults)
        XCTAssertNil(restored.activeSession)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(rootView: LibraryView(context: container.mainContext, workspace: restored, columnVisibility: .all)
            .modelContainer(container).modifier(AppAppearance()))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        // Repeated main-actor suspension/resumption catches the former non-yielding redraw loop.
        for _ in 0..<10 { try await settle(host.view) }
        XCTAssertEqual(restored.activeID, notebook.id)
        XCTAssertEqual(restored.activeSession?.ready, true)
        XCTAssertFalse(restored.blocksTabControls)
        let returned = await restored.showLibrary()
        XCTAssertTrue(returned)
        try await settle(host.view)
        let sort = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "library.sort" })
        XCTAssertTrue(sort.isEnabled)
        let name = try XCTUnwrap(sort.menu?.children.compactMap { $0 as? UIAction }.first { $0.title == "Name" })
        let activation = UIButton(type: .system)
        activation.addAction(name, for: .primaryActionTriggered)
        activation.sendActions(for: .primaryActionTriggered)
        try await settle(host.view)
        XCTAssertEqual(defaults.string(forKey: "library.sortOrder"), "name")
        let reopened = await restored.open(notebook)
        XCTAssertTrue(reopened)
        try await settle(host.view)
        XCTAssertEqual(defaults.data(forKey: "editor.quickPalette.v2"), paletteData)
        let retainedInk = try await storage.read(path)
        XCTAssertEqual(retainedInk, ink)
        withExtendedLifetime(container) {}
    }

    func testSortMenuPersistsCheckedChoiceAcrossLibraryReopening() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "library.sortOrder")
        defer {
            if let previous { defaults.set(previous, forKey: "library.sortOrder") }
            else { defaults.removeObject(forKey: "library.sortOrder") }
        }
        defaults.set("recent", forKey: "library.sortOrder")
        let container = try PersistenceController.makeContainer(inMemory: true)
        for (title, isPDF) in [("Biology", false), ("Lecture 2", false), ("Class Handout", true)] {
            let notebook = Notebook(title: title)
            let page = NotePage(pageIndex: 0)
            if isPDF { page.pdfFilePath = "Fixtures/handout.pdf" }
            container.mainContext.insert(notebook)
            container.mainContext.insert(page)
            notebook.pages = [page]
        }
        try container.mainContext.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(rootView: LibraryView(context: container.mainContext)
            .modelContainer(container).modifier(AppAppearance()))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        try await settle(host.view)
        let button = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "library.sort" })
        XCTAssertTrue(button.showsMenuAsPrimaryAction)
        let actions = try XCTUnwrap(button.menu).children.compactMap { $0 as? UIAction }
        XCTAssertEqual(actions.map(\.title), ["Name", "Recent", "Type"])
        let type = try XCTUnwrap(actions.first { $0.title == "Type" })
        let activation = UIButton(type: .system)
        activation.addAction(type, for: .primaryActionTriggered)
        activation.sendActions(for: .primaryActionTriggered)
        try await settle(host.view)
        XCTAssertEqual(defaults.string(forKey: "library.sortOrder"), "type")

        let reopened = UIHostingController(rootView: LibraryView(context: container.mainContext)
            .modelContainer(container).modifier(AppAppearance()))
        window.rootViewController = reopened
        reopened.view.frame = window.bounds
        try await settle(reopened.view)
        let restored = try XCTUnwrap(descendants(reopened.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "library.sort" })
        let restoredActions = try XCTUnwrap(restored.menu).children.compactMap { $0 as? UIAction }
        XCTAssertEqual(restoredActions.first { $0.title == "Type" }?.state, .on)
        XCTAssertEqual(restoredActions.first { $0.title == "Recent" }?.state, .off)
        let image = UIGraphicsImageRenderer(size: reopened.view.bounds.size).image { _ in
            reopened.view.drawHierarchy(in: reopened.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Library-Sort-By-Type"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime(container) {}
    }

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
