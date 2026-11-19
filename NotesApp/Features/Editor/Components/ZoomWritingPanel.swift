import SwiftUI
import PencilKit

struct ZoomWritingPanel: View {
    let session: EditorSession
    let tools: ToolPreferences
    let fingerDrawing: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Label("Zoom Writing", systemImage: EditorTool.writingZoom.symbol).font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Button { session.moveWritingRegion(horizontal: -0.8, vertical: 0) } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.accessibilityLabel("Move writing window left")
                Button { session.moveWritingRegion(horizontal: 0.8, vertical: 0) } label: { Image(systemName: "arrow.right").frame(width: 44, height: 44) }.accessibilityLabel("Move writing window right")
                Button { session.moveWritingRegion(horizontal: 0, vertical: 0.75) } label: { Image(systemName: "return").frame(width: 44, height: 44) }.accessibilityLabel("Next writing line")
                Button { Task { _ = await session.closeZoomWriting() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close zoom writing")
            }.padding(.horizontal, 12).disabled(session.auxiliaryInputActive || session.busy)
            ZoomWritingCanvas(session: session, tool: tools.tool, fingerDrawing: fingerDrawing,
                              allowsInk: tools.selected.inkType != nil || tools.selected == .lasso || tools.selected == .eraser && tools.eraserMode != .highlighter)
                .frame(height: 190).clipped().accessibilityIdentifier("editor.zoomWriting")
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 0.5) }
    }
}

final class ZoomWritingHost: UIScrollView, UIScrollViewDelegate {
    let paper: PaperView
    let objects: PageObjectsContentView
    let covers: PageObjectsInteractionView
    let ink: InkCanvas
    let pageSize: CGSize
    var region: CGRect = .zero { didSet { if region != oldValue { needsPosition = true; setNeedsLayout() } } }
    private var needsPosition = true
    private var lastSize = CGSize.zero
    init(size: CGSize) {
        pageSize = size
        let frame = CGRect(origin: .zero, size: size)
        paper = PaperView(frame: frame); objects = PageObjectsContentView(frame: frame); ink = InkCanvas(frame: frame); covers = PageObjectsInteractionView(frame: frame)
        super.init(frame: .zero)
        delegate = self; backgroundColor = .secondarySystemBackground
        maximumZoomScale = 6; minimumZoomScale = 0.25
        addSubview(paper); paper.addSubview(objects); paper.addSubview(ink); paper.addSubview(covers)
        covers.isUserInteractionEnabled = false
        paper.isUserInteractionEnabled = true
        objects.isUserInteractionEnabled = false; objects.backgroundColor = .clear; objects.isOpaque = false
        ink.isOpaque = false; ink.backgroundColor = .clear; ink.isScrollEnabled = false
        ink.delegate = ink
        ink.contentSize = size; ink.overrideUserInterfaceStyle = .light
        contentSize = size; showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        accessibilityLabel = "Magnified handwriting window. Write with Apple Pencil; use two fingers to pan."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, region.width > 0 else { return }
        let scale = min(traitCollection.displayScale, 2400 / max(pageSize.width, pageSize.height))
        paper.contentScaleFactor = scale; objects.contentScaleFactor = traitCollection.displayScale; covers.contentScaleFactor = scale
        if needsPosition || lastSize != bounds.size {
            needsPosition = false; lastSize = bounds.size
            zoomScale = min(6, max(0.25, min(bounds.width / region.width, bounds.height / region.height)))
            contentOffset = CGPoint(x: min(max(0, region.midX * zoomScale - bounds.width / 2), max(0, contentSize.width - bounds.width)),
                                    y: min(max(0, region.minY * zoomScale), max(0, contentSize.height - bounds.height)))
        }
        synchronizeInkViewport()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { paper }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { ink.beginViewportGesture() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        ink.endViewportGesture(); setNeedsLayout(); synchronizeInkViewport()
    }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout(); synchronizeInkViewport() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { synchronizeInkViewport() }
    private func synchronizeInkViewport() {
        guard !isZooming, !isZoomBouncing, bounds.width > 0, bounds.height > 0 else { return }
        ink.synchronizeViewport(pageSize: pageSize, visibleRect: paper.convert(bounds, from: self),
                                scale: zoomScale, displayScale: traitCollection.displayScale)
    }
}

struct ZoomWritingCanvas: UIViewRepresentable {
    let session: EditorSession
    let tool: PKTool
    let fingerDrawing: Bool
    let allowsInk: Bool
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> ZoomWritingHost {
        let host = ZoomWritingHost(size: session.page?.logicalSize ?? PageGeometry.size)
        host.ink.pageID = session.page?.id; host.ink.drawing = session.drawing
        host.ink.delegate = context.coordinator; session.zoomCanvas = host.ink
        return host
    }
    func updateUIView(_ host: ZoomWritingHost, context: Context) {
        guard host.ink.pageID == session.page?.id else { return }
        host.region = session.writingRegion ?? .zero
        host.paper.template = session.page?.paperTemplate ?? .blank
        host.paper.pdfImage = session.pdfBackground; host.paper.pdfContentSize = session.page?.contentSize
        host.objects.elements = session.elements; host.objects.images = session.objectImages
        host.covers.elements = session.elements; host.covers.revealed = session.revealedTapes
        host.ink.tool = tool; host.ink.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        host.ink.isUserInteractionEnabled = allowsInk && !session.busy
        host.panGestureRecognizer.minimumNumberOfTouches = 2
    }
    static func dismantleUIView(_ host: ZoomWritingHost, coordinator: Coordinator) {
        host.ink.delegate = nil
        if coordinator.session.zoomCanvas === host.ink {
            coordinator.session.zoomCanvas = nil; coordinator.session.auxiliaryInputActive = false
        }
    }
    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: EditorSession
        init(session: EditorSession) { self.session = session }
        func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
            (canvasView as? InkCanvas)?.canvasViewDidFinishRendering(canvasView)
        }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            guard session.zoomCanvas === canvasView else { return }; session.auxiliaryInputActive = true
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            guard session.zoomCanvas === canvasView else { return }; session.auxiliaryInputActive = false
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard session.zoomCanvas === canvasView, (canvasView as? InkCanvas)?.pageID == session.page?.id,
                  session.ready, canvasView.drawing != session.drawing else { return }
            session.changed(canvasView.drawing)
            // The overview stays visible and shares logical coordinates with this window.
            if session.canvas?.drawing != canvasView.drawing { session.canvas?.drawing = canvasView.drawing }
        }
    }
}
