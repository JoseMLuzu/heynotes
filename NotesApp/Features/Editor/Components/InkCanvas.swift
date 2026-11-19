import PencilKit

final class InkCanvas: PKCanvasView, PKCanvasViewDelegate {
    var pageID: UUID?
    private let history = UndoManager()
    private var viewportRefresh: Task<Void, Never>?
    private var refreshGeneration = 0
    private var hasRendered = false
    private var needsViewportRefresh = false
    private var viewportGestureActive = false
    override var undoManager: UndoManager? { history }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Only the outer page scroll view owns finger navigation. Enabling native
        // zoom for render quality must not enable a second, competing pinch.
        pinchGestureRecognizer?.isEnabled = false
        panGestureRecognizer.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // PencilKit reconfigures these recognizers during its own layout.
        pinchGestureRecognizer?.isEnabled = false
        panGestureRecognizer.isEnabled = false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pinchGestureRecognizer || gestureRecognizer === panGestureRecognizer { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func beginViewportGesture() {
        viewportGestureActive = true
        cancelViewportRefresh()
    }
    func endViewportGesture() {
        viewportGestureActive = false
        refreshViewportRendering()
    }

    /// The parent scroll view owns navigation. This viewport gives PencilKit its real
    /// magnification, while an inverse view transform preserves logical page geometry.
    /// Only a buffered screen region is allocated, including on very large PDF pages.
    @discardableResult
    func synchronizeViewport(pageSize: CGSize, visibleRect: CGRect, scale: CGFloat, displayScale: CGFloat) -> Bool {
        guard !viewportGestureActive, pageSize.width > 0, pageSize.height > 0, scale.isFinite, scale > 0 else { return false }
        let visible = visibleRect.intersection(CGRect(origin: .zero, size: pageSize))
        guard !visible.isNull, !visible.isEmpty else { return false }
        let state = drawingGestureRecognizer.state
        guard state != .began && state != .changed else { return false }
        // Native lasso keeps a stable, full-page surface: panning must not clip the
        // selection or replace its drawing. Its resolution stays fixed until tool exit.
        let nativeLasso = tool is PKLassoTool && isUserInteractionEnabled
        let scale = nativeLasso ? min(1, 2400 / max(1, displayScale) / max(pageSize.width, pageSize.height)) : scale
        let comfort = visible.insetBy(dx: -64 / scale, dy: -64 / scale)
            .intersection(CGRect(origin: .zero, size: pageSize))
        if !nativeLasso, abs(zoomScale - scale) < 0.0001, frame.contains(comfort) { return false }
        let maximumSide = 4096 / max(1, displayScale) / scale
        let width = nativeLasso ? pageSize.width : min(pageSize.width, visible.width * 3, maximumSide)
        let height = nativeLasso ? pageSize.height : min(pageSize.height, visible.height + 256 / scale, maximumSide)
        let rect = CGRect(x: min(max(0, visible.midX - width / 2), max(0, pageSize.width - width)),
                          y: min(max(0, visible.midY - height / 2), max(0, pageSize.height - height)), width: width, height: height)
        let nativeSize = CGSize(width: width * scale, height: height * scale)
        let offset = CGPoint(x: rect.minX * scale, y: rect.minY * scale)
        if abs(zoomScale - scale) < 0.0001, abs(frame.minX - rect.minX) < 0.01, abs(frame.minY - rect.minY) < 0.01,
           abs(bounds.width - nativeSize.width) < 0.01, abs(bounds.height - nativeSize.height) < 0.01,
           abs(contentOffset.x - offset.x) < 0.01, abs(contentOffset.y - offset.y) < 0.01 { return false }
        UIView.performWithoutAnimation {
            minimumZoomScale = 0.001; maximumZoomScale = 16
            contentInsetAdjustmentBehavior = .never; contentInset = .zero
            transform = .identity
            bounds = CGRect(origin: contentOffset, size: nativeSize)
            if abs(zoomScale - scale) >= 0.0001 { setZoomScale(scale, animated: false) }
            let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
            if contentSize != size { contentSize = size }
            setContentOffset(offset, animated: false)
            transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
            center = CGPoint(x: rect.midX, y: rect.midY)
        }
        if nativeLasso {
            cancelViewportRefresh()
            needsViewportRefresh = false
            let existing = drawing
            drawing = existing
        } else {
            needsViewportRefresh = true
            refreshViewportRendering()
        }
        return true
    }

    /// A disabled nested scroll view does not reliably invalidate its cached ink on
    /// programmatic zoom. Reuse the exact drawing (no serialization or new strokes).
    /// Coalesce layout callbacks and never reset a canvas during a Pencil stroke.
    private func refreshViewportRendering() {
        guard !viewportGestureActive, hasRendered, needsViewportRefresh, viewportRefresh == nil, window != nil, !drawing.strokes.isEmpty else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        viewportRefresh = Task { [weak self] in
            defer { if self?.refreshGeneration == generation { self?.viewportRefresh = nil } }
            do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            while !Task.isCancelled {
                guard let self, self.window != nil else { break }
                let state = self.drawingGestureRecognizer.state
                if state != .began && state != .changed {
                    if !(self.tool is PKLassoTool && self.isUserInteractionEnabled) {
                        self.layoutIfNeeded()
                        let existing = self.drawing
                        self.needsViewportRefresh = false
                        self.drawing = existing
                    }
                    break
                }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
            }
        }
    }

    // The active editor delegate forwards this callback; prepared canvases use self.
    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        hasRendered = true
        refreshViewportRendering()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelViewportRefresh() }
        else { refreshViewportRendering() }
    }

    private func cancelViewportRefresh() {
        refreshGeneration += 1
        viewportRefresh?.cancel(); viewportRefresh = nil
    }

    deinit { viewportRefresh?.cancel() }

    /// UIView touch coordinates include this scroll view's bounds/content offset.
    func pagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / zoomScale, y: point.y / zoomScale)
    }
}
