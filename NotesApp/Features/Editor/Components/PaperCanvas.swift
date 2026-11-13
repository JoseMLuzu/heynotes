import SwiftUI
import PencilKit

/// Fixed logical page coordinates shared by ink, templates, thumbnails and future export.
enum PageGeometry {
    static let size = CGSize(width: 768, height: 1086)
}

final class PaperView: UIView {
    var template: PaperTemplate = .blank { didSet { if oldValue != template { setNeedsDisplay() } } }
    var pdfImage: UIImage? { didSet { setNeedsDisplay() } }
    var pdfContentSize: CGSize? { didSet { if oldValue != pdfContentSize { setNeedsDisplay() } } }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PDFRendering.paper(template, size: bounds.size, in: context)
        if let pdfImage { pdfImage.draw(in: CGRect(origin: .zero, size: pdfContentSize ?? bounds.size)) }
    }
}

final class InkCanvas: PKCanvasView {
    var pageID: UUID?
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

private final class PagePanDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let host, let pan = gestureRecognizer as? UIPanGestureRecognizer,
              host.ink.drawingPolicy == .pencilOnly,
              abs(host.zoomScale - host.minimumZoomScale) < 0.01,
              !host.isZooming, !host.isZoomBouncing,
              host.ink.drawingGestureRecognizer.state != .began,
              host.ink.drawingGestureRecognizer.state != .changed,
              pan.numberOfTouches == 1 else { return false }
        let point = pan.location(in: host.objectControls)
        let translation = pan.translation(in: host.objectControls)
        let start = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
        guard !host.objectControls.fingerDragEditsObject(at: start) else { return false }
        let velocity = pan.velocity(in: host)
        return abs(velocity.x) > abs(velocity.y) * 1.25
    }
}

final class CanvasHost: UIScrollView, UIScrollViewDelegate {
    let paper: PaperView
    let ink: InkCanvas
    let pageSize: CGSize
    let objectContent: PageObjectsContentView
    let objectControls: PageObjectsInteractionView
    var objectsMode = false { didSet { updateInkInteraction() } }
    private let zoomContent: UIView
    private let pageSurface: UIView
    var onPageSwipe: ((Int, Bool) -> Void)?
    var onPagePull: ((CGFloat) -> Void)?
    var onPagePullCancelled: (() -> Void)?
    var onCreationProgress: ((Double?) -> Void)?
    var hasNextPage = true
    var hasPreviousPage = false
    var editorAllowsInk = true { didSet { updateInkInteraction() } }
    var transitionPausesInk = false { didSet { updateInkInteraction() } }
    let pagePan = UIPanGestureRecognizer()
    private let pagingDelegate = PagePanDelegate()
    private var startingOffset = CGPoint.zero
    private var fitted = false
    private var gestureViewport = CGSize.zero
    private var gesturePageID: UUID?
    private var lastTranslation = CGPoint.zero
    private var turnCommitted = false
    private var creationHold = PageCreationHold()
    private var creationTask: Task<Void, Never>?
    private var pullAnimator: UIViewPropertyAnimator?
    var isPagePullAnimating: Bool { pullAnimator != nil }
    private(set) var pageSwipeVelocity: CGFloat = 0
    var visiblePageOffset: CGFloat {
        let moving = pullAnimator != nil || transitionPausesInk
        let transform = moving ? (pageSurface.layer.presentation()?.affineTransform() ?? pageSurface.transform) : pageSurface.transform
        return transform.tx * zoomScale
    }
    init(pageSize: CGSize = PageGeometry.size) {
        self.pageSize = pageSize
        zoomContent = UIView(frame: CGRect(origin: .zero, size: pageSize))
        pageSurface = UIView(frame: CGRect(origin: .zero, size: pageSize))
        paper = PaperView(frame: CGRect(origin: .zero, size: pageSize))
        objectContent = PageObjectsContentView(frame: CGRect(origin: .zero, size: pageSize))
        objectControls = PageObjectsInteractionView(frame: CGRect(origin: .zero, size: pageSize))
        ink = InkCanvas(frame: CGRect(origin: .zero, size: pageSize))
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear; isOpaque = false
        panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pagingDelegate.host = self
        pagePan.delegate = pagingDelegate
        pagePan.addTarget(self, action: #selector(handlePagePan(_:)))
        pagePan.minimumNumberOfTouches = 1
        pagePan.maximumNumberOfTouches = 1
        pagePan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(pagePan)
        objectControls.yieldFingerGestures(to: pagePan)
        panGestureRecognizer.require(toFail: pagePan)
        maximumZoomScale = 4
        contentSize = pageSize
        addSubview(zoomContent); zoomContent.addSubview(pageSurface)
        pageSurface.addSubview(paper); paper.addSubview(objectContent); paper.addSubview(ink); paper.addSubview(objectControls)
        objectContent.backgroundColor = .clear; objectContent.isOpaque = false; objectContent.isUserInteractionEnabled = false
        objectControls.onPreview = { [weak objectContent] in objectContent?.elements = $0 }
        paper.isUserInteractionEnabled = true
        paper.layer.shadowColor = UIColor.black.cgColor
        paper.layer.shadowOpacity = 0.08
        paper.layer.shadowRadius = 10
        paper.layer.shadowOffset = CGSize(width: 0, height: 3)
        paper.layer.shadowPath = UIBezierPath(rect: paper.bounds).cgPath
        ink.isOpaque = false; ink.backgroundColor = .clear
        ink.isScrollEnabled = false
        ink.contentSize = pageSize
        ink.drawingPolicy = .pencilOnly
        ink.overrideUserInterfaceStyle = .light
        accessibilityLabel = "Handwriting page. At full-page view, flick left or right with one finger to turn pages. On the last page, pull left and hold to add a page. Pinch to zoom; drag to scroll when zoomed."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateInkInteraction() {
        ink.isUserInteractionEnabled = editorAllowsInk && !transitionPausesInk && !objectsMode
        objectControls.isUserInteractionEnabled = editorAllowsInk && !transitionPausesInk
    }
    /// Animate inside the zoom root, leaving the scroll viewport/background stationary.
    func setPageOffset(_ points: CGFloat) {
        pageSurface.transform = CGAffineTransform(translationX: points / max(zoomScale, 0.01), y: 0)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if gestureViewport != bounds.size { cancelPendingPageCreation() }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fit = min((bounds.width - 24) / pageSize.width, (bounds.height - 24) / pageSize.height)
        let wasAtFit = !fitted || abs(zoomScale - minimumZoomScale) < 0.01
        let minimum = max(0.01, fit)
        if minimumZoomScale != minimum { minimumZoomScale = minimum }
        let paperScale = min(traitCollection.displayScale, 2400 / max(pageSize.width, pageSize.height))
        if paper.contentScaleFactor != paperScale { paper.contentScaleFactor = paperScale }
        if objectContent.contentScaleFactor != paperScale { objectContent.contentScaleFactor = paperScale }
        if objectControls.contentScaleFactor != paperScale { objectControls.contentScaleFactor = paperScale }
        if wasAtFit, abs(zoomScale - minimumZoomScale) > 0.001 { zoomScale = minimumZoomScale }
        fitted = true
        objectControls.zoom = zoomScale
        let insets = UIEdgeInsets(top: max(12, (bounds.height - zoomContent.frame.height) / 2), left: max(12, (bounds.width - zoomContent.frame.width) / 2), bottom: 12, right: 12)
        if contentInset != insets { contentInset = insets }
    }
    @objc func handlePagePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            if isDecelerating { setContentOffset(contentOffset, animated: false) }
            if !transitionPausesInk { stopPagePullAnimation() }
            startingOffset = contentOffset
            gestureViewport = bounds.size; gesturePageID = ink.pageID
            turnCommitted = false; creationHold.reset()
            updatePagePull(pan)
        case .changed:
            guard !turnCommitted else { return }
            updatePagePull(pan)
        case .ended:
            pageSwipeVelocity = pan.velocity(in: self).x
            cancelPendingPageCreation()
            guard !turnCommitted else { return }
            let direction = PageSwipe.direction(translation: pan.translation(in: self), velocity: pan.velocity(in: self), viewportWidth: bounds.width)
            if validPageContext, let direction, (direction == 1 ? hasNextPage : hasPreviousPage), let onPageSwipe {
                turnCommitted = true; onPageSwipe(direction, false)
            } else { cancelInteractivePull() }
        case .cancelled, .failed:
            cancelPendingPageCreation()
            if !turnCommitted { cancelInteractivePull() }
        default: break
        }
    }

    private func updatePagePull(_ pan: UIPanGestureRecognizer) {
        lastTranslation = pan.translation(in: self)
        pageSwipeVelocity = pan.velocity(in: self).x
        if validPageContext && !transitionPausesInk && !UIAccessibility.isReduceMotionEnabled {
            let destination = lastTranslation.x < 0 ? hasNextPage : hasPreviousPage
            setPageOffset(PageTurnMotion.pull(lastTranslation.x, hasDestination: destination, viewportWidth: bounds.width))
            onPagePull?(lastTranslation.x)
        }
        updateCreationHold()
        // Existing-page turns commit on release, so reversing a drag never changes the page ID.
    }

    private func cancelInteractivePull() {
        if let onPagePullCancelled { onPagePullCancelled() } else { settlePagePull() }
    }

    private var validPageContext: Bool {
        isUserInteractionEnabled && ink.drawingPolicy == .pencilOnly && abs(zoomScale - minimumZoomScale) < 0.01 &&
        !isZooming && !isZoomBouncing && gestureViewport == bounds.size && gesturePageID == ink.pageID &&
        ink.drawingGestureRecognizer.state != .began && ink.drawingGestureRecognizer.state != .changed
    }

    private func updateCreationHold() {
        let eligible = validPageContext && !hasNextPage && !turnCommitted && pagePan.isEnabled &&
            (pagePan.state == .began || pagePan.state == .changed) && pagePan.numberOfTouches == 1 &&
            window?.windowScene?.activationState == .foregroundActive &&
            PageSwipe.isCreationPull(lastTranslation, viewportWidth: bounds.width)
        switch creationHold.update(eligible: eligible, now: CACurrentMediaTime()) {
        case .inactive:
            creationTask?.cancel(); creationTask = nil; onCreationProgress?(nil)
        case .progress(let progress):
            onCreationProgress?(progress)
            if creationTask == nil {
                creationTask = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                        guard let self else { return }
                        self.updateCreationHold()
                        if !self.creationHold.isWaiting { return }
                    }
                }
            }
        case .commit:
            turnCommitted = true
            creationTask?.cancel(); creationTask = nil; onCreationProgress?(nil)
            onPageSwipe?(1, true)
        }
    }

    func cancelPendingPageCreation() {
        creationTask?.cancel(); creationTask = nil
        creationHold.cancel(); onCreationProgress?(nil)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelPendingPageCreation() }
    }
    deinit { creationTask?.cancel() }

    func settlePagePull() {
        stopPagePullAnimation()
        contentOffset = startingOffset
        guard !UIAccessibility.isReduceMotionEnabled, abs(visiblePageOffset) > 0.1 else { setPageOffset(0); return }
        let animation = UIViewPropertyAnimator(duration: 0.18, dampingRatio: 1) { [weak self] in self?.setPageOffset(0) }
        animation.addCompletion { [weak self, weak animation] _ in
            if self?.pullAnimator === animation { self?.pullAnimator = nil }
        }
        pullAnimator = animation
        animation.startAnimation()
    }

    func stopPagePullAnimation() {
        let offset = visiblePageOffset
        pullAnimator?.stopAnimation(true); pullAnimator = nil
        setPageOffset(offset)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomContent }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout() }
}

struct PaperCanvas: UIViewRepresentable {
    let session: EditorSession
    let tool: PKTool
    let fingerDrawing: Bool
    var editorTool: EditorTool = .pen
    var inkStyle = InkStyle()
    var rulerEnabled = false
    var onPencilDoubleTap: ((UIPencilPreferredAction) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> PageCanvasContainer {
        let container = PageCanvasContainer()
        container.addInteraction(context.coordinator.pencil.interaction)
        return container
    }

    static func dismantleUIView(_ container: PageCanvasContainer, coordinator: Coordinator) {
        coordinator.pencil.detach()
        container.discardPreparedCanvases()
        coordinator.session.onPreparedNeighbor = nil
        coordinator.session.onDiscardPreparedCanvases = nil
    }

    func updateUIView(_ container: PageCanvasContainer, context: Context) {
        session.onPreparedNeighbor = { [weak container] in container?.prepare($0) }
        session.onDiscardPreparedCanvases = { [weak container] in container?.discardPreparedCanvases() }
        context.coordinator.pencil.interaction.isEnabled = isEnabled && session.ready && !session.busy
        context.coordinator.pencil.onTap = { [weak container, weak session] action in
            guard let host = container?.current, let session,
                  session.ready, !session.busy, !host.transitionPausesInk,
                  session.canvas === host.ink,
                  host.ink.drawingGestureRecognizer.state != .began,
                  host.ink.drawingGestureRecognizer.state != .changed else { return }
            onPencilDoubleTap?(action)
        }
        guard let page = session.page else { return }
        if container.pageID != page.id || container.current?.pageSize != page.logicalSize {
            let pageID = page.id
            let host = container.takePreparedCanvas(pageID: pageID, identity: session.preparedIdentity, size: page.logicalSize)
                ?? CanvasHost(pageSize: page.logicalSize)
            host.paper.pdfImage = session.pdfBackground
            host.ink.pageID = pageID
            if host.ink.drawing != session.drawing { host.ink.drawing = session.drawing }
            host.ink.delegate = context.coordinator
            host.objectControls.onCommit = { [weak session] item, new in
                guard let session else { return false }
                if new { return session.insertElement(item) }
                session.updateElement(item); return session.elements.contains(item)
            }
            host.objectControls.onSelect = { [weak session] in session?.selectedElementID = $0 }
            host.objectControls.onReveal = { [weak session] in session?.toggleTape($0) }
            host.onCreationProgress = { [weak container] in container?.showCreationProgress($0) }
            host.onPagePull = { [weak container] in container?.updateInteractivePull(from: pageID, translation: $0) }
            host.onPagePullCancelled = { [weak container] in container?.cancelInteractivePull() }
            host.onPageSwipe = { [weak session, weak host, weak container] direction, allowCreation in
                if !allowCreation { session?.prioritizePageTurn(direction) }
                container?.afterCurrentTurn { [weak session, weak host, weak container] in
                    Task {
                        guard session?.page?.id == pageID, session?.ready == true, session?.busy == false,
                              host?.window != nil, host?.pagePan.isEnabled == true,
                              host?.ink.drawingGestureRecognizer.state != .began,
                              host?.ink.drawingGestureRecognizer.state != .changed,
                              session?.canvas === host?.ink else {
                            container?.rejectPull(from: pageID); return
                        }
                        let originalID = session?.page?.id
                        container?.prepareTurn(from: pageID, direction: direction, reduceMotion: UIAccessibility.isReduceMotionEnabled,
                                               velocity: host?.pageSwipeVelocity ?? 0)
                        host?.editorAllowsInk = false
                        await session?.turnPage(direction, creatingIfNeeded: allowCreation)
                        // Keep the pull continuous into a successful turn; spring back on a boundary/failure.
                        if session?.page?.id == originalID || session?.ready != true {
                            container?.cancelPendingTurn(from: pageID)
                            host?.editorAllowsInk = session?.ready == true && session?.busy == false && host?.pagePan.isEnabled == true
                        }
                    }
                }
            }
            session.canvas = host.ink
            container.show(host, pageID: pageID, direction: session.pageTurnDirection, reduceMotion: reduceMotion,
                           identity: session.preparedIdentity)
        }
        guard let host = container.current else { return }
        var neighborIDs: [Int: UUID] = [:]
        for direction in [-1, 1] {
            neighborIDs[direction] = session.notebook.pages.first { $0.pageIndex == page.pageIndex + direction }?.id
        }
        container.retainNeighbors(neighborIDs)
        for prepared in session.preparedNeighbors { container.prepare(prepared) }
        // Tool/metadata updates never replace the live drawing or its undo history.
        if !sameTool(host.ink.tool, tool) { host.ink.tool = tool }
        host.hasNextPage = page.pageIndex < session.notebook.pages.count - 1
        host.hasPreviousPage = page.pageIndex > 0
        host.pagePan.isEnabled = isEnabled && !fingerDrawing && session.ready && !session.busy
        host.objectsMode = editorTool.editsObjects
        host.editorAllowsInk = isEnabled && session.ready && !session.busy
        host.ink.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        host.panGestureRecognizer.minimumNumberOfTouches = fingerDrawing || editorTool.editsObjects ? 2 : 1
        host.paper.template = page.paperTemplate
        host.paper.pdfContentSize = page.contentSize
        host.ink.isRulerActive = rulerEnabled && editorTool.inkType != nil
        host.objectContent.images = session.objectImages
        host.objectContent.elements = session.elements
        host.objectContent.isHidden = !session.elements.contains { $0.kind != .tape }
        host.objectControls.isHidden = !editorTool.editsObjects && !session.elements.contains { $0.kind == .tape }
        host.objectControls.elements = session.elements
        host.objectControls.revealed = session.revealedTapes
        host.objectControls.selectedID = session.selectedElementID
        host.objectControls.tool = editorTool
        host.objectControls.fingerDrawing = fingerDrawing
        host.objectControls.style = inkStyle
    }
    private func sameTool(_ lhs: PKTool, _ rhs: PKTool) -> Bool {
        if let lhs = lhs as? PKInkingTool, let rhs = rhs as? PKInkingTool { return lhs == rhs }
        if let lhs = lhs as? PKEraserTool, let rhs = rhs as? PKEraserTool { return lhs == rhs }
        return lhs is PKLassoTool && rhs is PKLassoTool
    }

    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: EditorSession
        let pencil = PencilDoubleTapCoordinator()
        init(session: EditorSession) { self.session = session }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Late callbacks from an outgoing page must never overwrite the incoming page.
            guard session.canvas === canvasView, (canvasView as? InkCanvas)?.pageID == session.page?.id,
                  canvasView.drawing != session.drawing else { return }
            session.changed(canvasView.drawing)
        }
    }
}
