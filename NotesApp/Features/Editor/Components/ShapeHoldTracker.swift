import UIKit

/// Gesture-independent state used by the Pencil observer and deterministic native tests.
/// Screen-space pause tolerances stay consistent at every page magnification.
@MainActor final class ShapeHoldTracker {
    var onBegin: (() -> Void)?
    var onMatch: ((SmartShapeMatch?) -> Void)?
    var onEnd: ((Bool) -> Void)?
    private let holdDelay: Duration
    private var points: [CGPoint] = []
    private var anchor = CGPoint.zero
    private var scale: CGFloat = 1
    private var timer: Task<Void, Never>?
    private var generation = 0
    private var active = false
    private var matched = false

    init(holdDelay: Duration = .milliseconds(400)) { self.holdDelay = holdDelay }
    func begin(at point: CGPoint, screenPoint: CGPoint, screenScale: CGFloat) {
        reset(); active = true; points = [point]; anchor = screenPoint
        scale = max(0.01, screenScale); onBegin?(); schedule()
    }
    func append(_ samples: [CGPoint], screenPoint: CGPoint) {
        guard active else { return }
        for point in samples where point.x.isFinite && point.y.isFinite {
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) * scale < 0.4 { continue }
            if points.count >= 4096 { points = points.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil } }
            points.append(point)
        }
        let tolerance: CGFloat = matched ? 12 : 6
        if hypot(screenPoint.x - anchor.x, screenPoint.y - anchor.y) > tolerance {
            anchor = screenPoint
            if matched { matched = false; onMatch?(nil) }
            schedule()
        }
    }
    func end(cancelled: Bool = false) {
        guard active else { return }
        active = false; generation += 1; timer?.cancel(); timer = nil
        if cancelled { matched = false; onMatch?(nil) }
        onEnd?(matched)
        points = []; matched = false
    }
    func reset() {
        if active { end(cancelled: true) }
        generation += 1; timer?.cancel(); timer = nil; points = []; matched = false
    }
    private func schedule() {
        generation += 1; let token = generation
        timer?.cancel()
        timer = Task { [weak self, holdDelay] in
            do { try await Task.sleep(for: holdDelay) } catch { return }
            guard let self, self.active, self.generation == token else { return }
            let match = SmartShapeGeometry.match(self.points, minimumSize: 24 / self.scale)
            self.matched = match != nil; self.timer = nil
            self.onMatch?(match)
        }
    }
    deinit { timer?.cancel() }
}
