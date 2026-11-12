import XCTest
import SwiftUI
import PencilKit
@testable import NotesApp

@MainActor final class DocumentOpeningTests: XCTestCase {
    func testTileOpeningFrameFollowsScrollWithoutObservableLibraryState() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Scroll origin"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let origin = NotebookOpeningFrame()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 500)
        let host = UIHostingController(rootView: ScrollView {
            VStack {
                LibraryNotebookTile(notebook: notebook, storage: .shared, openingFrame: origin) { _ in }
                    .frame(width: 200)
                Color.clear.frame(height: 1000)
            }
        }.modelContainer(container))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let initial = try XCTUnwrap(origin.rect)
        XCTAssertGreaterThan(initial.width, 0); XCTAssertGreaterThan(initial.height, 0)
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }
            .first { $0.contentSize.height > $0.bounds.height + 200 })
        let oldOffset = scroll.contentOffset.y
        scroll.setContentOffset(CGPoint(x: 0, y: oldOffset + 100), animated: false)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let moved = try XCTUnwrap(origin.rect)
        XCTAssertEqual(moved.minY, initial.minY - 100, accuracy: 0.5)
        XCTAssertEqual(moved.width, initial.width, accuracy: 0.5)
        XCTAssertEqual(moved.height, initial.height, accuracy: 0.5)
        withExtendedLifetime(container) {}
    }

    func testZoomKeepsTheSameCanvasSizeIdentityAndInk() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Opening"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let points = [CGPoint(x: 40, y: 70), CGPoint(x: 280, y: 140)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        session.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        let original = session.drawing
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let source = CGRect(x: 80, y: 120, width: 180, height: 220)
        func view(_ progress: CGFloat) -> some View {
            EditorView(session: session, onLibrary: {})
                .modifier(DocumentOpeningZoom(sourceFrame: source, progress: progress))
        }
        let host = UIHostingController(rootView: view(0))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        await Task.yield()
        let canvas = try XCTUnwrap(session.canvas), bounds = canvas.bounds
        XCTAssertGreaterThan(bounds.width, 0); XCTAssertGreaterThan(bounds.height, 0)
        for progress: CGFloat in [0, 0.5, 1] {
            host.rootView = view(progress); host.view.layoutIfNeeded()
            await Task.yield()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            XCTAssertTrue(session.canvas === canvas)
            XCTAssertEqual(canvas.bounds, bounds)
            XCTAssertEqual(canvas.drawing, original)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Document-Zoom-\(progress)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
