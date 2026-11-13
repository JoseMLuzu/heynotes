import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class TabCloseTransitionTests: XCTestCase {
    func testClosingActiveTabRetainsEditorUntilSuccessorLoadsInEitherSlot() async throws {
        for secondaryOnly in [false, true] {
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suite = "TabClose.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
            let container = try PersistenceController.makeContainer(inMemory: true)
            let context = container.mainContext, storage = DrawingStorage(root: root)
            func notebook(_ title: String) -> Notebook {
                let book = Notebook(title: title), page = NotePage(pageIndex: 0)
                context.insert(book); context.insert(page); book.pages = [page]; return book
            }
            let a = notebook("First notebook"), b = notebook("Next notebook")
            try context.save()
            let workspace = DocumentWorkspace(context: context, storage: storage, defaults: defaults)
            await workspace.restore()
            _ = await workspace.open(a)
            if secondaryOnly {
                _ = await workspace.openBeside(b); _ = await workspace.closeSplit()
            } else {
                _ = await workspace.open(b); _ = await workspace.open(a)
            }
            let outgoing = try XCTUnwrap(workspace.activeSession)
            let successor = secondaryOnly ? a : b
            let slot = workspace.focusedPane
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
            let host = UIHostingController(rootView: LibraryView(context: context, workspace: workspace).modelContainer(container))
            window.rootViewController = host; window.isHidden = false
            defer {
                window.isHidden = true; window.rootViewController = nil
                workspace.discardPreparedPages()
            }
            host.view.frame = window.bounds; try await settle(host.view)
            let canvas = try XCTUnwrap(outgoing.canvas), toolbar = try XCTUnwrap(button("editor.pageOptions", in: host.view))
            XCTAssertFalse(outgoing.hasPendingSave)
            let gate = TabReadGate()
            let blockedRead = Task.detached { await storage.holdForTabCloseTest(gate) }
            defer { gate.open() }
            for _ in 0..<200 {
                if gate.hasEntered { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertTrue(gate.hasEntered)
            let closing = Task { await workspace.close(outgoing.notebook.id) }
            for _ in 0..<200 {
                if workspace.isSwitching { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            try await settle(host.view)
            XCTAssertTrue(workspace.isSwitching)
            XCTAssertTrue(workspace.activeSession === outgoing, "Keep the outgoing editor while the next file is loading")
            XCTAssertTrue(outgoing.canvas === canvas)
            XCTAssertTrue(workspace.openNotebooks.contains { $0.id == outgoing.notebook.id })
            XCTAssertTrue(button("editor.pageOptions", in: host.view) === toolbar)
            XCTAssertNil(button("library.sort", in: host.view), "Library must never render between two tabs")
            capture(window, name: "Tab-Close-Loading-\(slot)")
            gate.open(); await blockedRead.value
            let closed = await closing.value; XCTAssertTrue(closed)
            try await settle(host.view)
            XCTAssertEqual(workspace.activeID, successor.id)
            XCTAssertEqual(workspace.focusedPane, slot)
            XCTAssertEqual(workspace.visiblePanes, [slot])
            XCTAssertTrue(workspace.activeSession?.ready == true)
            XCTAssertTrue(button("editor.pageOptions", in: host.view) === toolbar)
            XCTAssertNil(button("library.sort", in: host.view))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Notebook>()), 2)
            capture(window, name: "Tab-Close-Ready-\(slot)")
            let lastClosed = await workspace.close(successor.id); XCTAssertTrue(lastClosed)
            try await settle(host.view)
            XCTAssertNil(workspace.activeSession)
            XCTAssertTrue(workspace.openNotebooks.isEmpty)
            XCTAssertNotNil(button("library.sort", in: host.view), "The last tab should intentionally return to Library")
            withExtendedLifetime(container) {}
        }
    }

    private func button(_ id: String, in view: UIView) -> UIButton? {
        ([view] + view.subviews.flatMap(descendants)).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == id }
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func settle(_ view: UIView) async throws {
        view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(120)); view.layoutIfNeeded()
    }
    private func capture(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private final class TabReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private let release = DispatchSemaphore(value: 0)
    var hasEntered: Bool { lock.withLock { entered } }
    func hold() {
        lock.withLock { entered = true }
        _ = release.wait(timeout: .now() + 5)
    }
    func open() { release.signal() }
}

private extension DrawingStorage {
    /// Test-only synchronous work holds this isolated storage executor, never the main actor.
    func holdForTabCloseTest(_ gate: TabReadGate) { gate.hold() }
}
