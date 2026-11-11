import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class ToolbarInteractionTests: XCTestCase {
    func testTouchPolicyChangesOnlyTheNearestScrollView() {
        let page = UIScrollView(), toolbar = UIScrollView(), content = UIView()
        page.delaysContentTouches = true; toolbar.delaysContentTouches = true
        page.addSubview(toolbar); toolbar.addSubview(content)
        let probe = ImmediateScrollTouchPolicy.Probe()
        content.addSubview(probe)
        probe.configureScrollView()
        XCTAssertFalse(toolbar.delaysContentTouches)
        XCTAssertTrue(toolbar.canCancelContentTouches)
        XCTAssertTrue(page.delaysContentTouches, "The toolbar policy must never change page/canvas scrolling.")
    }

    func testEditorToolbarFitsAndOverflowScrollKeepsTheSameCanvas() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Toolbar"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: EditorView(session: session, onLibrary: {})
            .environment(\.horizontalSizeClass, .regular))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        var canvas: PKCanvasView?
        for width: CGFloat in [1366, 720, 1024] {
            window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            let current = try XCTUnwrap(session.canvas)
            if let canvas { XCTAssertTrue(current === canvas) } else { canvas = current }
            let probes = descendants(host.view).compactMap { $0 as? ImmediateScrollTouchPolicy.Probe }
            if width == 720 { XCTAssertFalse(probes.isEmpty, "A narrow toolbar must retain accessible horizontal overflow.") }
            for probe in probes {
                let scroll = try XCTUnwrap(nearestScroll(to: probe))
                XCTAssertFalse(scroll.delaysContentTouches)
                XCTAssertTrue(scroll.canCancelContentTouches)
                XCTAssertFalse(scroll === current)
            }
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Editor-Toolbar-\(Int(width))"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    private func nearestScroll(to view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let candidate = ancestor {
            if let scroll = candidate as? UIScrollView { return scroll }
            ancestor = candidate.superview
        }
        return nil
    }
}
