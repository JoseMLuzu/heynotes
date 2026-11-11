import XCTest
import SwiftUI
import PencilKit
@testable import NotesApp

@MainActor final class DocumentOpeningTests: XCTestCase {
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
