import UIKit
import os

/// One active canvas and up to two prepared neighbors. Ink stays editable, without raster snapshots.
final class PageCanvasContainer: UIView {
    private(set) var current: CanvasHost?
    private(set) var pageID: UUID?
    private var currentIdentity: UUID?
    private(set) var animator: UIViewPropertyAnimator?
    private var queuedTurn: (() -> Void)?
    private(set) var followUpTailDuration: TimeInterval?
    private var pendingPageID: UUID?
    private var pendingVelocity: CGFloat = 0
    private final class PreviewTurn {
        let source: CanvasHost
        let destination: CanvasHost
        let direction: Int
        let sourceIdentity: UUID?
        var validated = false
        var completed = false
        init(source: CanvasHost, destination: CanvasHost, direction: Int, sourceIdentity: UUID?) {
            self.source = source; self.destination = destination; self.direction = direction
            self.sourceIdentity = sourceIdentity
        }
    }
    private var previewTurn: PreviewTurn?
    private(set) var turnDistance: CGFloat = 0
    private(set) var turnDuration: TimeInterval = 0
    private struct WarmCanvas {
        let identity: UUID
        let host: CanvasHost
    }
    private var neighbors: [UUID: WarmCanvas] = [:]
    private var allowedNeighbors: [Int: UUID] = [:]
    private var pendingPreparation: [UUID: PreparedCanvasPage] = [:]
    private var warming: Task<Void, Never>?
    private var warmGeneration = 0
    private var turnTrace: OSSignpostIntervalState?
    private(set) var interactiveNeighbor: CanvasHost?
    private var interactiveDirection = 0
    var preparedCanvasCount: Int { neighbors.count }
    private let creationIndicator = PageCreationIndicator(effect: UIBlurEffect(style: .systemMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppTheme.canvasUIColor; isOpaque = true
        addSubview(creationIndicator)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func showCreationProgress(_ progress: Double?) { creationIndicator.show(progress: progress) }

    func retainNeighbors(_ ids: [Int: UUID]) {
        allowedNeighbors = ids
        let allowed = Set(ids.values)
        for id in Array(neighbors.keys) where !allowed.contains(id) {
            let removed = neighbors.removeValue(forKey: id)?.host
            if removed !== current { removed?.removeFromSuperview() }
        }
        pendingPreparation = pendingPreparation.filter { allowed.contains($0.key) }
    }

    /// Yield between native view allocations; never build speculative canvases during a Pencil stroke.
    func prepare(_ page: PreparedCanvasPage) {
        guard allowedNeighbors.values.contains(page.id), page.id != pageID,
              neighbors[page.id]?.identity != page.content.identity else { return }
        pendingPreparation[page.id] = page
        guard warming == nil else { return }
        let generation = warmGeneration
        warming = Task { [weak self] in
            defer { if self?.warmGeneration == generation { self?.warming = nil } }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
                guard let self, let item = self.pendingPreparation.values.first else { return }
                let state = self.current?.ink.drawingGestureRecognizer.state
                let finger = self.current?.pagePan.state
                if state == .began || state == .changed || finger == .began || finger == .changed ||
                    self.animator != nil || self.interactiveNeighbor != nil || self.pendingPageID != nil ||
                    self.current?.isPagePullAnimating == true || self.current?.isDecelerating == true { continue }
                self.pendingPreparation.removeValue(forKey: item.id)
                guard self.allowedNeighbors.values.contains(item.id), item.id != self.pageID else { continue }
                if self.neighbors[item.id]?.identity == item.content.identity { continue }
                self.neighbors.removeValue(forKey: item.id)?.host.removeFromSuperview()
                let preparing = PageTurnDiagnostics.signposter.beginInterval("PrepareNeighborCanvas", id: PageTurnDiagnostics.signposter.makeSignpostID())
                let host = item.makeHost()
                host.frame = self.bounds
                self.insertSubview(host, at: 0)
                host.layoutIfNeeded()
                host.setPageOffset(PageTurnMotion.distance(viewportWidth: self.bounds.width))
                self.neighbors[item.id] = WarmCanvas(identity: item.content.identity, host: host)
                PageTurnDiagnostics.signposter.endInterval("PrepareNeighborCanvas", preparing)
                PageTurnDiagnostics.signposter.emitEvent("NeighborCanvasPrepared")
            }
        }
    }

    func takePreparedCanvas(pageID: UUID, identity: UUID?, size: CGSize) -> CanvasHost? {
        guard let prepared = neighbors.removeValue(forKey: pageID) else { return nil }
        guard prepared.identity == identity, prepared.host.pageSize == size else {
            if interactiveNeighbor === prepared.host { interactiveNeighbor = nil }
            prepared.host.removeFromSuperview(); return nil
        }
        PageTurnDiagnostics.signposter.emitEvent("PreparedCanvasReused")
        return prepared.host
    }

    func discardPreparedCanvases() {
        warmGeneration += 1
        warming?.cancel(); warming = nil; pendingPreparation = [:]
        cancelInteractivePull()
        for entry in neighbors.values { entry.host.removeFromSuperview() }
        neighbors = [:]
    }

    /// Both sheets track the finger. The session/page ID changes only after release and a safe save.
    func updateInteractivePull(from id: UUID, translation: CGFloat) {
        guard pageID == id, animator == nil, pendingPageID == nil, let current else { return }
        let direction = translation < 0 ? 1 : -1
        let next = allowedNeighbors[direction].flatMap { neighbors[$0]?.host }
        if interactiveNeighbor !== next {
            interactiveNeighbor?.setPageOffset(PageTurnMotion.distance(viewportWidth: bounds.width) * CGFloat(interactiveDirection))
            interactiveNeighbor = next
            if let next { insertSubview(next, belowSubview: current) }
        }
        interactiveDirection = direction
        guard let next else { return }
        let distance = PageTurnMotion.distance(viewportWidth: bounds.width) * CGFloat(direction)
        if next.frame != bounds { next.frame = bounds; next.layoutIfNeeded() }
        next.setPageOffset(distance + current.visiblePageOffset)
    }

    func cancelInteractivePull() {
        if previewTurn?.validated == true { finishTurn() }
        if let pending = stopPreviewAtVisiblePosition() {
            interactiveNeighbor = pending.destination; interactiveDirection = pending.direction
            pendingPageID = nil; endTurnTrace()
        }
        guard let current, let preview = interactiveNeighbor, animator == nil else {
            if animator == nil { current?.settlePagePull() }
            return
        }
        interactiveNeighbor = nil
        let distance = PageTurnMotion.distance(viewportWidth: bounds.width) * CGFloat(interactiveDirection)
        current.transitionPausesInk = true
        let animation = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18, dampingRatio: 1) {
            current.setPageOffset(0); preview.setPageOffset(distance)
        }
        animation.addCompletion { [weak self] _ in
            current.transitionPausesInk = false
            self?.animator = nil
            let followUp = self?.queuedTurn; self?.queuedTurn = nil; followUp?()
        }
        animator = animation; animation.startAnimation()
    }

    deinit { warming?.cancel() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Rotation/resizing finishes a pending turn before laying out the viewport.
        if current?.bounds.size != bounds.size {
            queuedTurn = nil
            if previewTurn?.validated == false { _ = stopPreviewAtVisiblePosition(); endTurnTrace() }
            finishTurn(); pendingPageID = nil
            interactiveNeighbor = nil
            for neighbor in neighbors.values {
                neighbor.host.frame = bounds
                neighbor.host.layoutIfNeeded()
                neighbor.host.setPageOffset(PageTurnMotion.distance(viewportWidth: bounds.width))
            }
            current?.setPageOffset(0)
            current?.frame = bounds
            current?.transitionPausesInk = false
        } else if animator == nil && pendingPageID == nil { current?.frame = bounds }
        let width = min(152, max(0, bounds.width - 24))
        let preferredHeight = max(112, UIFont.preferredFont(forTextStyle: .caption1).lineHeight * 2 + 64)
        let height = min(preferredHeight, max(0, bounds.height - 24))
        creationIndicator.frame = CGRect(x: max(12, bounds.width - width - 16), y: max(12, (bounds.height - height) / 2), width: width, height: height)
    }

    private func finishTurn() {
        let active = animator
        animator = nil
        active?.stopAnimation(false)
        active?.finishAnimation(at: .end)
    }

    /// Accept one quick follow-up flick without snapping a sheet that is still entering.
    func afterCurrentTurn(_ action: @escaping () -> Void) {
        guard let animator else { action(); return }
        let alreadyQueued = queuedTurn != nil
        queuedTurn = action
        guard !alreadyQueued, animator.state == .active, animator.isInterruptible else { return }
        let duration = PageTurnMotion.followUpDuration(duration: animator.duration, progress: animator.fractionComplete)
        guard duration > 0 else { return }
        animator.pauseAnimation()
        followUpTailDuration = duration
        animator.continueAnimation(withTimingParameters: nil, durationFactor: CGFloat(duration / animator.duration))
    }

    /// Move an already-prepared sheet immediately. Publishing/editing still waits for a safe open.
    func prepareTurn(from pageID: UUID, direction: Int, reduceMotion: Bool, velocity: CGFloat = 0) {
        guard self.pageID == pageID, pendingPageID == nil, let current else { return }
        finishTurn()
        current.stopPagePullAnimation()
        pendingPageID = pageID
        pendingVelocity = velocity
        endTurnTrace()
        turnTrace = PageTurnDiagnostics.signposter.beginInterval("ReleaseToSettledSheet", id: PageTurnDiagnostics.signposter.makeSignpostID())
        guard !reduceMotion, bounds.width > 0,
              let nextID = allowedNeighbors[direction], let destination = neighbors[nextID]?.host else { return }
        let pending = PreviewTurn(source: current, destination: destination, direction: direction, sourceIdentity: currentIdentity)
        previewTurn = pending
        let distance = PageTurnMotion.distance(viewportWidth: bounds.width) * CGFloat(direction)
        destination.frame = bounds; destination.layoutIfNeeded()
        destination.setPageOffset(distance + current.visiblePageOffset)
        insertSubview(destination, belowSubview: current)
        current.transitionPausesInk = true; destination.transitionPausesInk = true
        turnDistance = distance
        turnDuration = PageTurnMotion.duration(distance: distance + current.visiblePageOffset, velocity: velocity)
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.3, y: 1))
        let animation = UIViewPropertyAnimator(duration: turnDuration, timingParameters: timing)
        animation.addAnimations { current.setPageOffset(-distance); destination.setPageOffset(0) }
        animation.addCompletion { [weak self] _ in
            guard let self, self.previewTurn === pending else { return }
            self.animator = nil; pending.completed = true
            if pending.validated { self.completeValidatedPreview(pending) }
        }
        animator = animation; animation.startAnimation()
    }

    func cancelPendingTurn(from pageID: UUID) {
        guard self.pageID == pageID, pendingPageID == pageID, current != nil else { return }
        if let pending = stopPreviewAtVisiblePosition() {
            interactiveNeighbor = pending.destination; interactiveDirection = pending.direction
        } else { finishTurn() }
        pendingPageID = nil
        endTurnTrace()
        cancelInteractivePull()
    }

    func show(_ incoming: CanvasHost, pageID: UUID, direction: Int, reduceMotion: Bool, identity: UUID? = nil) {
        if let pending = previewTurn, pending.destination === incoming {
            pending.validated = true
            pendingPageID = nil; interactiveNeighbor = nil
            self.pageID = pageID; current = incoming
            currentIdentity = identity
            pending.source.cancelPendingPageCreation()
            pending.source.isUserInteractionEnabled = false; pending.source.accessibilityElementsHidden = true
            incoming.isUserInteractionEnabled = true; incoming.accessibilityElementsHidden = false
            bringSubviewToFront(incoming); bringSubviewToFront(creationIndicator)
            PageTurnDiagnostics.signposter.emitEvent("CanvasInstalled")
            if reduceMotion, !pending.completed { finishTurn() }
            else if pending.completed { completeValidatedPreview(pending) }
            return
        }
        // The validated content may differ from speculation. Keep the visible source pose.
        if let stale = stopPreviewAtVisiblePosition() {
            stale.destination.removeFromSuperview()
            if let id = stale.destination.ink.pageID { neighbors.removeValue(forKey: id) }
        }
        let interactiveOffset = interactiveNeighbor === incoming ? incoming.visiblePageOffset : nil
        interactiveNeighbor = nil
        let velocity = pendingPageID == self.pageID ? pendingVelocity : 0
        queuedTurn = nil
        finishTurn()
        pendingPageID = nil
        let outgoing = current
        let outgoingIdentity = currentIdentity
        outgoing?.cancelPendingPageCreation()
        self.pageID = pageID
        current = incoming
        currentIdentity = identity
        clipsToBounds = true
        incoming.frame = bounds
        addSubview(incoming)
        bringSubviewToFront(creationIndicator)
        incoming.layoutIfNeeded()
        PageTurnDiagnostics.signposter.emitEvent("CanvasInstalled")
        incoming.isUserInteractionEnabled = true
        incoming.accessibilityElementsHidden = false
        turnDistance = 0; turnDuration = 0
        followUpTailDuration = nil
        guard let outgoing else { incoming.setPageOffset(0); endTurnTrace(); return }
        guard bounds.width > 0 else { outgoing.removeFromSuperview(); endTurnTrace(); return }
        outgoing.isUserInteractionEnabled = false
        outgoing.accessibilityElementsHidden = true
        // Keep finger paging responsive; only Pencil ink pauses until the short motion ends.
        incoming.isUserInteractionEnabled = true
        incoming.transitionPausesInk = true
        guard !reduceMotion else {
            incoming.setPageOffset(0); outgoing.removeFromSuperview(); incoming.transitionPausesInk = false; endTurnTrace(); return
        }
        let paperWidth = max(outgoing.pageSize.width * outgoing.zoomScale, incoming.pageSize.width * incoming.zoomScale)
        let distance = PageTurnMotion.distance(viewportWidth: bounds.width, renderedPageWidth: paperWidth) * CGFloat(direction)
        let offset = min(abs(distance), max(-abs(distance), outgoing.visiblePageOffset))
        incoming.setPageOffset(interactiveOffset ?? (distance + offset))
        turnDistance = distance
        turnDuration = PageTurnMotion.duration(distance: distance + offset, velocity: velocity)
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.3, y: 1))
        let animation = UIViewPropertyAnimator(duration: turnDuration, timingParameters: timing)
        animation.addAnimations {
            incoming.setPageOffset(0)
            outgoing.setPageOffset(-distance)
        }
        animation.addCompletion { [weak self] _ in
            self?.retire(outgoing, identity: outgoingIdentity)
            incoming.transitionPausesInk = false
            self?.animator = nil
            self?.endTurnTrace()
            let followUp = self?.queuedTurn
            self?.queuedTurn = nil
            followUp?()
        }
        animator = animation
        animation.startAnimation()
    }

    private func endTurnTrace() {
        if let turnTrace { PageTurnDiagnostics.signposter.endInterval("ReleaseToSettledSheet", turnTrace) }
        turnTrace = nil
    }

    private func completeValidatedPreview(_ pending: PreviewTurn) {
        guard previewTurn === pending else { return }
        previewTurn = nil; animator = nil
        pending.source.transitionPausesInk = false
        retire(pending.source, identity: pending.sourceIdentity)
        pending.destination.transitionPausesInk = false
        endTurnTrace()
        let followUp = queuedTurn; queuedTurn = nil; followUp?()
    }

    /// Stop without invoking an endpoint completion: failure/rotation must preserve the visible pose.
    private func stopPreviewAtVisiblePosition() -> PreviewTurn? {
        guard let pending = previewTurn else { return nil }
        let sourceOffset = pending.source.visiblePageOffset
        let destinationOffset = pending.destination.visiblePageOffset
        previewTurn = nil
        animator?.stopAnimation(true); animator = nil
        pending.source.transitionPausesInk = false; pending.destination.transitionPausesInk = false
        pending.source.setPageOffset(sourceOffset); pending.destination.setPageOffset(destinationOffset)
        return pending
    }

    func rejectPull(from id: UUID) {
        guard pageID == id else { return }
        if pendingPageID == id { cancelPendingTurn(from: id) }
        else { cancelInteractivePull() }
    }

    /// Keep a clean return page's real canvas. Fresh source checks still gate every activation.
    private func retire(_ host: CanvasHost, identity: UUID?) {
        guard let id = host.ink.pageID, let identity, allowedNeighbors.values.contains(id), neighbors[id] == nil else {
            host.removeFromSuperview(); return
        }
        host.ink.delegate = nil
        host.onPageSwipe = nil; host.onPagePull = nil; host.onPagePullCancelled = nil
        host.editorAllowsInk = false; host.isUserInteractionEnabled = false; host.accessibilityElementsHidden = true
        host.objectControls.selectedID = nil; host.objectControls.revealed = []
        let direction = allowedNeighbors.first { $0.value == id }?.key ?? -1
        host.setPageOffset(PageTurnMotion.distance(viewportWidth: bounds.width) * CGFloat(direction))
        neighbors[id] = WarmCanvas(identity: identity, host: host)
        PageTurnDiagnostics.signposter.emitEvent("OutgoingCanvasRetained")
    }
}
