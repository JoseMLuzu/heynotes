import PencilKit

@MainActor final class SmartShapeCoordinator: NSObject {
    let observer = ShapeHoldObserver(target: nil, action: nil)
    private weak var canvas: InkCanvas?
    private weak var session: EditorSession?
    private var before: PKDrawing?
    private var match: SmartShapeMatch?
    private var pageID: UUID?
    private var style = InkStyle()
    private var strokeStyle = InkStyle()
    private var lifted = false
    private var nativeEnded = false
    private var generation = UUID()
    private var finishing: Task<Void, Never>?
    private let preview = CAShapeLayer()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(cancel), name: UIApplication.willResignActiveNotification, object: nil)
        observer.onBegin = { [weak self] in
            guard let self else { return }
            self.finishing?.cancel(); self.generation = UUID(); self.before = self.canvas?.drawing
            self.finishing = nil; self.strokeStyle = self.style
            self.pageID = self.canvas?.pageID; self.lifted = false; self.nativeEnded = false; self.match = nil
            self.show(nil)
        }
        observer.onMatch = { [weak self] match in self?.match = match; self?.show(match) }
        observer.onEnd = { [weak self] success in
            self?.lifted = success
            if !success { self?.match = nil; self?.show(nil) }
            else { self?.finishIfReady() }
        }
        preview.fillColor = nil; preview.lineWidth = 2; preview.lineDashPattern = [4, 3]
        preview.strokeColor = UIColor.systemBlue.cgColor
    }
    func attach(to canvas: InkCanvas, session: EditorSession, enabled: Bool, style: InkStyle) {
        if self.canvas !== canvas {
            cancel()
            self.canvas?.removeGestureRecognizer(observer); preview.removeFromSuperlayer()
            self.canvas = canvas; canvas.addGestureRecognizer(observer); canvas.layer.addSublayer(preview)
        }
        self.session = session; self.style = style
        if observer.isEnabled != enabled { observer.isEnabled = enabled }
        if !enabled { cancel() }
    }
    func didEnd(_ canvas: PKCanvasView) {
        guard self.canvas === canvas else { return }
        nativeEnded = true; finishIfReady()
    }
    func didChange(_ canvas: PKCanvasView) {
        if self.canvas === canvas { finishIfReady() }
    }
    private func finishIfReady() {
        guard finishing == nil, nativeEnded, lifted, let match, let before, let pageID,
              let canvas, canvas.pageID == pageID, canvas.drawing.strokes.count == before.strokes.count + 1 else { return }
        let token = generation, style = strokeStyle
        finishing = Task { [weak self, weak canvas] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.generation == token, let canvas, let session = self.session else { return }
            defer { if self.generation == token { self.finishing = nil } }
            let snapshot = canvas.drawing
            _ = await session.applySmartShape(match, before: before, snapshot: snapshot, pageID: pageID, style: style)
            if self.generation == token { self.match = nil; self.show(nil) }
        }
    }
    private func show(_ match: SmartShapeMatch?) {
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        guard let match else { preview.path = nil; return }
        let path: UIBezierPath
        if match.kind == .ellipse { path = UIBezierPath(ovalIn: match.rect) }
        else if match.kind == .rectangle { path = UIBezierPath(rect: match.rect) }
        else {
            path = UIBezierPath()
            path.move(to: CGPoint(x: match.rect.minX, y: match.reversed ? match.rect.maxY : match.rect.minY))
            path.addLine(to: CGPoint(x: match.rect.maxX, y: match.reversed ? match.rect.minY : match.rect.maxY))
        }
        var transform = CGAffineTransform(scaleX: canvas?.zoomScale ?? 1, y: canvas?.zoomScale ?? 1)
        preview.path = path.cgPath.copy(using: &transform)
    }
    @objc func cancel() {
        generation = UUID(); finishing?.cancel(); finishing = nil
        observer.tracker.reset(); before = nil; match = nil; lifted = false; nativeEnded = false; show(nil)
    }
    func detach() { cancel(); canvas?.removeGestureRecognizer(observer); preview.removeFromSuperlayer(); canvas = nil }
}
