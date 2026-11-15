import UIKit

/// Coordinates are the same logical page points as PencilKit, objects and PDF export.
final class StudentToolOverlay: UIView {
    var mode: EditorTool? { didSet { if mode != oldValue { reset(); configure() } } }
    var fingerDrawing = false { didSet { if oldValue != fingerDrawing { configure() } } }
    var radius: CGFloat = 16
    var laserStyle = InkStyle(red: 1, green: 0.15, blue: 0.2, width: 3) {
        didSet { if oldValue != laserStyle { laser.style = laserStyle } }
    }
    var onActivity: ((Bool) -> Void)?
    var onErase: (([CGPoint], CGFloat) -> Void)?
    var onCircle: ((CGRect) -> Void)?
    var onTap: ((EditorTool, CGPoint) -> Void)?
    var onRegion: ((EditorTool, CGRect) -> Void)?
    private(set) var isTracking = false
    private var points: [CGPoint] = []
    private var vertices: [CGPoint] = []
    private let pan = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private let laser = LaserPointerVisual()
    private var fade: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear; isOpaque = false
        pan.addTarget(self, action: #selector(drag(_:))); pan.maximumNumberOfTouches = 1
        tap.addTarget(self, action: #selector(tapped(_:))); tap.require(toFail: pan)
        addGestureRecognizer(pan); addGestureRecognizer(tap)
        laser.style = laserStyle
        layer.addSublayer(laser.layer); configure()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        laser.layer.frame = bounds
        CATransaction.commit()
    }
    func yieldFingerGestures(to pagePan: UIGestureRecognizer) { pan.require(toFail: pagePan); tap.require(toFail: pagePan) }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { mode != nil && bounds.contains(point) }
    private func configure() {
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue), finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
        pan.allowedTouchTypes = fingerDrawing ? [pencil, finger] : [pencil]
        tap.allowedTouchTypes = [pencil, finger]
        pan.isEnabled = mode != nil && mode != .stamp && mode != .sticky && mode != .protractor
        tap.isEnabled = mode != nil
        isAccessibilityElement = mode == .protractor
        accessibilityLabel = "Protractor. Tap the vertex, then one point on each arm. A fourth tap starts a new measurement."
    }
    func reset() {
        fade?.cancel(); fade = nil; laser.clear()
        points = []; vertices = []; isTracking = false; onActivity?(false); setNeedsDisplay()
    }
    private func bounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(bounds.maxX, max(0, point.x)), y: min(bounds.maxY, max(0, point.y)))
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let mode else { return }
        let point = bounded(gesture.location(in: self))
        switch gesture.state {
        case .began:
            let delta = gesture.translation(in: self)
            points = [bounded(CGPoint(x: point.x - delta.x, y: point.y - delta.y)), point]
            fade?.cancel(); laser.layer.removeAllAnimations()
            isTracking = true; onActivity?(true); updateLaser(); if mode != .laser { setNeedsDisplay() }
        case .changed:
            if points.count < 4096 { points.append(point) } else { points[points.count - 1] = point }
            updateLaser(); if mode != .laser { setNeedsDisplay() }
        case .ended:
            points.append(point)
            if mode == .laser { updateLaser(); fadeLaser() }
            else if mode == .eraser { onErase?(points, radius) }
            else if let start = points.first {
                if mode == .compass, let circle = StudentToolGeometry.circle(center: start, end: point, bounds: bounds) { onCircle?(circle) }
                else if [.capture, .cardCapture, .pdfHighlight, .writingZoom].contains(mode) {
                    onRegion?(mode, CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(start.x - point.x), height: abs(start.y - point.y)))
                }
            }
            points = []; isTracking = false; onActivity?(false); if mode != .laser { setNeedsDisplay() }
        case .cancelled, .failed: reset()
        default: break
        }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let mode else { return }
        let point = bounded(gesture.location(in: self))
        if mode == .protractor {
            if vertices.count == 3 { vertices = [] }; vertices.append(point); setNeedsDisplay()
            if vertices.count == 3, let angle = StudentToolGeometry.angle(vertex: vertices[0], first: vertices[1], second: vertices[2]) {
                accessibilityValue = "\(angle.formatted(.number.precision(.fractionLength(1)))) degrees"
                UIAccessibility.post(notification: .announcement, argument: accessibilityValue)
            }
        } else if mode == .laser {
            points = [point, CGPoint(x: point.x + 0.1, y: point.y)]; updateLaser(); points = []; fadeLaser()
        } else if mode == .eraser { onErase?([point], radius) }
        else if mode == .stamp || mode == .sticky { onTap?(mode, point) }
    }
    private func updateLaser() {
        guard mode == .laser else { return }
        laser.show(points)
    }
    private func fadeLaser() {
        fade?.cancel(); laser.fadeOut()
        fade = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }; self?.laser.clear()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if mode == .protractor { MeasurementToolRenderer.protractor(vertices, in: context) }
        guard let start = points.first, let end = points.last else { return }
        context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(1.5)
        if mode == .compass, let circle = StudentToolGeometry.circle(center: start, end: end, bounds: bounds) {
            context.strokeEllipse(in: circle)
            MeasurementToolRenderer.label("r = \(Double(circle.width / 2).formatted(.number.precision(.fractionLength(1)))) pt", at: end, in: context)
        } else if mode == .eraser { context.strokeEllipse(in: CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2)) }
        else if [.capture, .cardCapture, .pdfHighlight, .writingZoom].contains(mode ?? .pen) {
            let selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.08).cgColor); context.fill(selection)
            context.setLineDash(phase: 0, lengths: [5, 3]); context.stroke(selection)
        }
    }
    deinit { fade?.cancel() }
}
