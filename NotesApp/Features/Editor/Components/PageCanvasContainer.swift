import UIKit

/// Retains both real canvases only for the short page turn; no ink rasterization is needed.
final class PageCanvasContainer: UIView {
    private(set) var current: CanvasHost?
    private(set) var pageID: UUID?
    private var animator: UIViewPropertyAnimator?
    private var pendingPageID: UUID?
    private let creationIndicator = PageCreationIndicator(effect: UIBlurEffect(style: .systemMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppTheme.canvasUIColor; isOpaque = true
        addSubview(creationIndicator)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func showCreationProgress(_ progress: Double?) { creationIndicator.show(progress: progress) }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Rotation/resizing finishes a pending turn before laying out the viewport.
        if current?.bounds.size != bounds.size {
            finishTurn(); pendingPageID = nil
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

    /// Retain the current page unchanged until its replacement is ready; no pre-flash/recoil.
    func prepareTurn(from pageID: UUID, direction: Int, reduceMotion: Bool) {
        guard self.pageID == pageID, pendingPageID == nil, current != nil else { return }
        finishTurn()
        pendingPageID = pageID
    }

    func cancelPendingTurn(from pageID: UUID) {
        guard self.pageID == pageID, pendingPageID == pageID, let current else { return }
        finishTurn(); pendingPageID = nil
        current.setPageOffset(0)
    }

    func show(_ incoming: CanvasHost, pageID: UUID, direction: Int, reduceMotion: Bool) {
        finishTurn()
        pendingPageID = nil
        let outgoing = current
        outgoing?.cancelPendingPageCreation()
        self.pageID = pageID
        current = incoming
        clipsToBounds = true
        incoming.frame = bounds
        addSubview(incoming)
        bringSubviewToFront(creationIndicator)
        incoming.layoutIfNeeded()
        guard let outgoing, bounds.width > 0 else { return }
        outgoing.isUserInteractionEnabled = false
        // Keep finger paging responsive; only Pencil ink pauses until the short motion ends.
        incoming.isUserInteractionEnabled = true
        incoming.transitionPausesInk = true
        guard !reduceMotion else {
            outgoing.removeFromSuperview(); incoming.transitionPausesInk = false; return
        }
        let distance = min(44, max(24, bounds.width * 0.03)) * CGFloat(direction)
        incoming.setPageOffset(distance)
        let animation = UIViewPropertyAnimator(duration: 0.14, curve: .easeOut) {
            incoming.setPageOffset(0)
            outgoing.setPageOffset(-distance * 0.6)
        }
        animation.addCompletion { [weak self] _ in
            outgoing.removeFromSuperview()
            incoming.transitionPausesInk = false
            self?.animator = nil
        }
        animator = animation
        animation.startAnimation()
    }
}
