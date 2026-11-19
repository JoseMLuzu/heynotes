import UIKit

/// Observes Pencil movement without preventing or delaying PencilKit's recognizers.
final class ShapeHoldObserver: UIGestureRecognizer {
    var onBegin: (() -> Void)?
    var onMatch: ((SmartShapeMatch?) -> Void)?
    var onEnd: ((Bool) -> Void)?
    private var points: [CGPoint] = []
    private var anchor = CGPoint.zero
    private var timer: Task<Void, Never>?
    private var matched = false
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first, let view else { state = .failed; return }
        let location = touch.location(in: view)
        anchor = (view as? InkCanvas)?.pagePoint(fromViewPoint: location) ?? location
        points = [anchor]; matched = false; onBegin?(); state = .began
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        let location = touch.location(in: view)
        let point = (view as? InkCanvas)?.pagePoint(fromViewPoint: location) ?? location
        if points.count < 4096 { points.append(point) }
        if hypot(point.x - anchor.x, point.y - anchor.y) > 2 {
            anchor = point; timer?.cancel(); matched = false; onMatch?(nil)
            let snapshot = points
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                guard let self else { return }
                let match = SmartShapeGeometry.match(snapshot)
                self.matched = match != nil; self.onMatch?(match)
            }
        }
        state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { timer?.cancel(); onEnd?(matched); state = .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { timer?.cancel(); onMatch?(nil); onEnd?(false); state = .cancelled }
    override func reset() { super.reset(); timer?.cancel(); points = []; matched = false }
    deinit { timer?.cancel() }
}
