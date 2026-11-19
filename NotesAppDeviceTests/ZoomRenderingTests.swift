import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class ZoomRenderingTests: XCTestCase {
    func testSmallInitialPinchIncrementsAreNotSnappedBackToFit() throws {
        let host = CanvasHost(), window = try show(host)
        defer { close(window) }
        let fit = host.minimumZoomScale
        for delta: CGFloat in [0.002, 0.004, 0.008, 0.02] {
            let target = fit + delta
            host.setZoomScale(target, animated: false)
            host.setNeedsLayout(); host.layoutIfNeeded()
            XCTAssertEqual(host.zoomScale, target, accuracy: 0.0001)
        }
    }

    func testOnlyOuterViewportOwnsFingerZoomAndInkGeometryWaitsUntilRelease() throws {
        let host = CanvasHost(), window = try show(host)
        defer { close(window) }
        XCTAssertFalse(host.ink.pinchGestureRecognizer?.isEnabled ?? true)
        XCTAssertFalse(host.ink.panGestureRecognizer.isEnabled)
        XCTAssertTrue(host.pinchGestureRecognizer?.isEnabled ?? false)
        let previousZoom = host.ink.zoomScale, previousBounds = host.ink.bounds
        host.scrollViewWillBeginZooming(host, with: host.paper)
        host.setZoomScale(3, animated: false); host.layoutIfNeeded()
        XCTAssertEqual(host.ink.zoomScale, previousZoom)
        XCTAssertEqual(host.ink.bounds, previousBounds)
        host.scrollViewDidEndZooming(host, with: host.paper, atScale: 3)
        host.layoutIfNeeded()
        XCTAssertEqual(host.zoomScale, 3, accuracy: 0.001)
        XCTAssertEqual(host.ink.zoomScale, 3, accuracy: 0.001)
        XCTAssertFalse(host.ink.pinchGestureRecognizer?.isEnabled ?? true)
    }

    func testZoomRefreshPreservesSavedInkCompoundUndoAndEditDate() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let book = Notebook(title: "Zoom QA"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
        try container.mainContext.save()
        let storage = DrawingStorage(root: root)
        let session = EditorSession(notebook: book, context: container.mainContext, storage: storage)
        await session.open(page)
        defer { session.discardPreparedPages() }
        let host = CanvasHost(), window = try show(host)
        defer { close(window) }
        let coordinator = PaperCanvas.Coordinator(session: session)
        host.ink.pageID = page.id; session.canvas = host.ink; host.ink.delegate = coordinator
        let drawing = ink()
        var text = PageElement(kind: .text, rect: CGRect(x: 90, y: 120, width: 160, height: 30))
        text.text = "Small handwriting"; text.fontSize = 12; text.fontName = HandwritingFont.defaultName
        XCTAssertTrue(session.replaceHandwritingContent(drawing, items: [text], action: "Mixed content"))
        host.objectContent.elements = session.elements
        let saved = await session.flush(); XCTAssertTrue(saved)
        let modified = page.updatedAt, path = try XCTUnwrap(page.drawingFilePath)
        let bytes = try await storage.read(path)
        // Exercise an already rendered page, then immediate repeated zoom/pan callbacks.
        try await Task.sleep(for: .milliseconds(200))
        for scale: CGFloat in [2, 3, 4] {
            host.setZoomScale(scale, animated: false)
            host.setContentOffset(CGPoint(x: 300, y: 380), animated: false)
            host.layoutIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(host.ink.zoomScale, host.zoomScale, accuracy: 0.001)
        XCTAssertEqual(host.ink.drawing, drawing)
        XCTAssertEqual(host.ink.drawing.dataRepresentation(), drawing.dataRepresentation())
        XCTAssertEqual(session.drawing, drawing); XCTAssertFalse(session.hasPendingSave)
        XCTAssertEqual(page.updatedAt, modified)
        let persisted = try await storage.read(path); XCTAssertEqual(persisted, bytes)
        host.ink.undoManager?.undo()
        XCTAssertTrue(session.drawing.strokes.isEmpty); XCTAssertTrue(session.elements.isEmpty)
        host.ink.undoManager?.redo()
        XCTAssertEqual(session.drawing, drawing); XCTAssertEqual(session.elements, [text])
        let finalSave = await session.flush(); XCTAssertTrue(finalSave)
    }

    func testExistingInkRendersAgainAfterImmediateHighZoom() async throws {
        let host = CanvasHost(), window = try show(host)
        defer { close(window) }
        let probe = ZoomRenderProbe(); host.ink.delegate = probe
        let source = ink(); host.ink.drawing = source
        host.setZoomScale(4, animated: false)
        host.setContentOffset(CGPoint(x: 300, y: 380), animated: false)
        host.layoutIfNeeded()
        // A first completion can still belong to the old viewport. The source-preserving
        // refresh must produce another completion rather than leave that cached render.
        for _ in 0..<100 {
            if probe.finishes >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(probe.finishes, 2)
        XCTAssertEqual(host.ink.drawing, source)
        XCTAssertEqual(host.ink.zoomScale, 4, accuracy: 0.001)
    }

    func testPageAndTouchCoordinatesStayStableWhileZoomingAndPanning() throws {
        let host = CanvasHost(), window = try show(host)
        defer { close(window) }
        for scale: CGFloat in [1, 2, 4, 1] {
            host.setZoomScale(scale, animated: false)
            for offset in [CGPoint.zero, CGPoint(x: 300, y: 380)] {
                host.setContentOffset(offset, animated: false); host.layoutIfNeeded()
                let logical = CGPoint(x: 200, y: 240)
                assertCoordinates(logical, canvas: host.ink, paper: host.paper)
                XCTAssertEqual(host.ink.zoomScale, host.zoomScale, accuracy: 0.001)
            }
        }
    }

    func testHugePDFViewportIsBoundedAndNativeLassoKeepsFullPageReachability() {
        let size = CGSize(width: 14400, height: 14400)
        let paper = UIView(frame: CGRect(origin: .zero, size: size))
        let canvas = InkCanvas(frame: paper.bounds); paper.addSubview(canvas)
        let visible = CGRect(x: 12000, y: 13000, width: 200, height: 180)
        XCTAssertTrue(canvas.synchronizeViewport(pageSize: size, visibleRect: visible, scale: 4, displayScale: 2))
        XCTAssertLessThanOrEqual(canvas.bounds.width * 2, 4096)
        XCTAssertLessThanOrEqual(canvas.bounds.height * 2, 4096)
        XCTAssertTrue(canvas.frame.contains(visible))
        assertCoordinates(CGPoint(x: 12050, y: 13050), canvas: canvas, paper: paper)
        XCTAssertFalse(canvas.synchronizeViewport(pageSize: size, visibleRect: visible, scale: 4, displayScale: 2))
        canvas.tool = PKLassoTool()
        XCTAssertTrue(canvas.synchronizeViewport(pageSize: size, visibleRect: visible, scale: 4, displayScale: 2))
        XCTAssertEqual(canvas.frame.width, size.width, accuracy: 0.01)
        XCTAssertEqual(canvas.frame.height, size.height, accuracy: 0.01)
        XCTAssertLessThanOrEqual(canvas.bounds.width * 2, 2400.01)
        XCTAssertFalse(canvas.synchronizeViewport(pageSize: size, visibleRect: CGRect(x: 100, y: 100, width: 200, height: 180), scale: 2, displayScale: 2))
        assertCoordinates(CGPoint(x: 100, y: 100), canvas: canvas, paper: paper)
    }

    func testZoomWritingWindowUsesNativeResolutionAndLogicalCoordinates() async throws {
        let host = ZoomWritingHost(size: PageGeometry.size), window = try show(host)
        defer { close(window) }
        host.region = CGRect(x: 60, y: 100, width: 120, height: 100)
        host.layoutIfNeeded()
        let probe = ZoomRenderProbe(); host.ink.delegate = probe; host.ink.drawing = ink()
        host.region = CGRect(x: 120, y: 300, width: 100, height: 100)
        host.layoutIfNeeded()
        XCTAssertEqual(host.ink.zoomScale, host.zoomScale, accuracy: 0.001)
        assertCoordinates(CGPoint(x: 150, y: 330), canvas: host.ink, paper: host.paper)
        for _ in 0..<100 {
            if probe.finishes >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(probe.finishes, 2)
    }

    func testTiledSmallTextMatchesHighResolutionRenderingAndUpdatesItsCache() throws {
        let content = PageObjectsContentView(frame: CGRect(x: 0, y: 0, width: 14400, height: 14400))
        let tiles = try XCTUnwrap(content.layer as? PageObjectsTileLayer)
        var text = PageElement(kind: .text, rect: CGRect(x: 900, y: 1200, width: 160, height: 30))
        text.text = "Small handwriting"; text.fontSize = 12; text.fontName = HandwritingFont.defaultName
        let patch = CGRect(x: 895, y: 1195, width: 175, height: 45)
        for message in ["Small handwriting", "Updated handwriting"] {
            text.text = message; content.elements = [text]
            let high = render(patch, scale: 8) { PageElementRenderer.draw([text], images: [:], in: $0) }
            let tiled = render(patch, scale: 8) { tiles.draw(in: $0) }
            XCTAssertEqual(tiled.pngData(), high.pngData())
            let low = render(patch, scale: 1) { PageElementRenderer.draw([text], images: [:], in: $0) }
            let enlarged = render(CGRect(origin: .zero, size: patch.size), scale: 8) { _ in low.draw(in: CGRect(origin: .zero, size: patch.size)) }
            XCTAssertNotEqual(tiled.pngData(), enlarged.pngData(), "Tiles must rerender glyph edges rather than enlarge a page bitmap")
        }
    }

    private func ink() -> PKDrawing {
        PKDrawing(strokes: (0..<4).map { column in
            let points = (0...10).map { index in
                PKStrokePoint(location: CGPoint(x: 90 + CGFloat(column) * 4, y: 150 + CGFloat(index)),
                    timeOffset: Double(index) * 0.02, size: CGSize(width: 0.5, height: 0.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
        })
    }
    private func show(_ view: UIView) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        let controller = UIViewController(); window.rootViewController = controller
        view.frame = window.bounds; controller.view.addSubview(view)
        window.makeKeyAndVisible(); view.layoutIfNeeded()
        return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func assertCoordinates(_ point: CGPoint, canvas: InkCanvas, paper: UIView, file: StaticString = #filePath, line: UInt = #line) {
        let native = paper.convert(point, to: canvas)
        let recovered = canvas.pagePoint(fromViewPoint: native)
        XCTAssertEqual(recovered.x, point.x, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(recovered.y, point.y, accuracy: 0.01, file: file, line: line)
    }
    private func render(_ patch: CGRect, scale: CGFloat, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: patch.size, format: format).image {
            UIColor.white.setFill(); $0.fill(CGRect(origin: .zero, size: patch.size))
            $0.cgContext.translateBy(x: -patch.minX, y: -patch.minY); draw($0.cgContext)
        }
    }
}

@MainActor private final class ZoomRenderProbe: NSObject, PKCanvasViewDelegate {
    var finishes = 0
    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        finishes += 1
        (canvasView as? InkCanvas)?.canvasViewDidFinishRendering(canvasView)
    }
}
