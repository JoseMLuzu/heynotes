import UIKit

/// Observes actual (not predicted) Pencil samples without delaying PencilKit input.
final class ShapeHoldObserver: UIGestureRecognizer {
    let tracker = ShapeHoldTracker()
    var onBegin: (() -> Void)? { get { tracker.onBegin } set { tracker.onBegin = newValue } }
    var onMatch: ((SmartShapeMatch?) -> Void)? { get { tracker.onMatch } set { tracker.onMatch = newValue } }
    var onEnd: ((Bool) -> Void)? { get { tracker.onEnd } set { tracker.onEnd = newValue } }
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first, let view else { state = .failed; return }
        let point = pagePoint(touch, in: view)
        let origin = view.convert(CGPoint.zero, to: nil)
        let unit = view.convert(CGPoint(x: (view as? InkCanvas)?.zoomScale ?? 1, y: 0), to: nil)
        tracker.begin(at: point, screenPoint: touch.preciseLocation(in: view.window), screenScale: hypot(unit.x - origin.x, unit.y - origin.y))
        state = .began
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        tracker.append((event.coalescedTouches(for: touch) ?? [touch]).map { pagePoint($0, in: view) },
                       screenPoint: touch.preciseLocation(in: view.window))
        state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view {
            tracker.append([pagePoint(touch, in: view)], screenPoint: touch.preciseLocation(in: view.window))
        }
        tracker.end(); state = .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { tracker.end(cancelled: true); state = .cancelled }
    override func reset() { super.reset(); tracker.reset() }
    private func pagePoint(_ touch: UITouch, in view: UIView) -> CGPoint {
        let point = touch.preciseLocation(in: view)
        return (view as? InkCanvas)?.pagePoint(fromViewPoint: point) ?? point
    }
}
