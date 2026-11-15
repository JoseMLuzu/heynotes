import UIKit

/// Temporary vector light. Concentric strokes avoid a full-page blurred offscreen surface.
@MainActor final class LaserPointerVisual {
    let layer = CALayer()
    private let glowLayers = (0..<3).map { _ in CAShapeLayer() }
    private let beam = CAShapeLayer()
    private let core = CAShapeLayer()
    private let headGlow = CAGradientLayer()
    private let head = CAShapeLayer()
    var style = InkStyle(red: 1, green: 0.15, blue: 0.2, width: 3) {
        didSet { if style != oldValue { configureStyle() } }
    }

    init() {
        for stroke in glowLayers + [beam, core] {
            stroke.fillColor = nil; stroke.lineCap = .round; stroke.lineJoin = .round
            layer.addSublayer(stroke)
        }
        headGlow.type = .radial
        headGlow.startPoint = CGPoint(x: 0.5, y: 0.5); headGlow.endPoint = CGPoint(x: 1, y: 1)
        headGlow.locations = [0, 0.25, 0.6, 1]
        layer.addSublayer(headGlow); layer.addSublayer(head)
        configureStyle(); clear()
    }

    private var beamWidth: CGFloat { max(1.2, min(7.2, style.width * 0.6)) }
    private var glowRadius: CGFloat { 12 + beamWidth * 2.5 }

    private func configureStyle() {
        withoutAnimation {
            let color = style.uiColor.withAlphaComponent(1)
            for (index, values) in [(12.0, 0.035), (7.0, 0.08), (3.0, 0.22)].enumerated() {
                glowLayers[index].lineWidth = beamWidth + values.0
                glowLayers[index].strokeColor = color.withAlphaComponent(values.1 * style.opacity).cgColor
            }
            beam.lineWidth = beamWidth
            beam.strokeColor = color.withAlphaComponent(0.92 * style.opacity).cgColor
            core.lineWidth = max(0.65, beamWidth * 0.32)
            core.strokeColor = UIColor.white.withAlphaComponent(0.95 * style.opacity).cgColor
            headGlow.colors = [0.9, 0.42, 0.1, 0].map { color.withAlphaComponent($0 * style.opacity).cgColor }
            head.fillColor = UIColor.white.withAlphaComponent(style.opacity).cgColor
            head.strokeColor = color.withAlphaComponent(style.opacity).cgColor
            head.lineWidth = max(0.8, beamWidth * 0.3)
        }
    }

    func show(_ points: [CGPoint]) {
        guard let first = points.first, let last = points.last else { clear(); return }
        let path = UIBezierPath(); path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        // A tap still has a round, luminous spot even without a line segment.
        withoutAnimation {
            layer.removeAllAnimations(); layer.opacity = 1
            for stroke in glowLayers + [beam, core] { stroke.path = path.cgPath }
            headGlow.isHidden = false
            headGlow.frame = CGRect(x: last.x - glowRadius, y: last.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
            let radius = max(1.8, beamWidth * 0.85)
            head.path = UIBezierPath(ovalIn: CGRect(x: last.x - radius, y: last.y - radius, width: radius * 2, height: radius * 2)).cgPath
        }
    }

    func fadeOut() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1; animation.toValue = 0; animation.duration = 0.9
        animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "fade")
    }

    func clear() {
        withoutAnimation {
            layer.removeAllAnimations(); layer.opacity = 1
            for stroke in glowLayers + [beam, core] { stroke.path = nil }
            head.path = nil; headGlow.isHidden = true
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true); body(); CATransaction.commit()
    }
}
