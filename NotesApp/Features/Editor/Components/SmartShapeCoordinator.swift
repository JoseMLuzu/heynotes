import PencilKit

@MainActor final class SmartShapeCoordinator {
    let observer = ShapeHoldObserver(target: nil, action: nil)
    private weak var canvas: InkCanvas?
    private weak var session: EditorSession?
    private var before: PKDrawing?
    private var match: SmartShapeMatch?
    private var pageID: UUID?
    private var style = InkStyle()
    private var lifted = false
    private var nativeEnded = false
    private var generation = UUID()
    private var finishing: Task<Void, Never>?
    private let preview = CAShapeLayer()

    init() {
        observer.onBegin = { [weak self] in
            guard let self else { return }
            self.finishing?.cancel(); self.generation = UUID(); self.before = self.canvas?.drawing
            self.pageID = self.canvas?.pageID; self.lifted = false; self.nativeEnded = false; self.match = nil
        }
        observer.onMatch = { [weak self] match in self?.match = match; self?.show(match) }
        observer.onEnd = { [weak self] success in
            self?.lifted = success
            if !success { self?.match = nil; self?.show(nil) }
            else if let self, self.nativeEnded, let canvas = self.canvas { self.didChange(canvas) }
        }
        preview.fillColor = nil; preview.lineWidth = 2; preview.lineDashPattern = [4, 3]
        preview.strokeColor = UIColor.systemBlue.cgColor
    }
    func attach(to canvas: InkCanvas, session: EditorSession, enabled: Bool, style: InkStyle) {
        if self.canvas !== canvas {
            self.canvas?.removeGestureRecognizer(observer); preview.removeFromSuperlayer(); finishing?.cancel(); generation = UUID()
            self.canvas = canvas; canvas.addGestureRecognizer(observer); canvas.layer.addSublayer(preview)
        }
        self.session = session; self.style = style
        observer.isEnabled = enabled
        if !enabled { finishing?.cancel(); match = nil; show(nil) }
    }
    func didEnd(_ canvas: PKCanvasView) { if self.canvas === canvas { nativeEnded = true } }
    func didChange(_ canvas: PKCanvasView) {
        guard nativeEnded, lifted, let match, let before, let pageID, self.canvas === canvas else { return }
        finishing?.cancel()
        let token = generation, style = style
        finishing = Task { [weak self, weak canvas] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.generation == token, let canvas, let session = self.session else { return }
            let snapshot = canvas.drawing
            _ = await session.applySmartShape(match, before: before, snapshot: snapshot, pageID: pageID, style: style)
            if self.generation == token { self.match = nil; self.show(nil) }
        }
    }
    private func show(_ match: SmartShapeMatch?) {
        guard let match else { preview.path = nil; return }
        let path: UIBezierPath
        if match.kind == .ellipse { path = UIBezierPath(ovalIn: match.rect) }
        else if match.kind == .rectangle { path = UIBezierPath(rect: match.rect) }
        else {
            path = UIBezierPath()
            path.move(to: CGPoint(x: match.rect.minX, y: match.reversed ? match.rect.maxY : match.rect.minY))
            path.addLine(to: CGPoint(x: match.rect.maxX, y: match.reversed ? match.rect.minY : match.rect.maxY))
        }
        preview.path = path.cgPath
    }
    func detach() { finishing?.cancel(); canvas?.removeGestureRecognizer(observer); preview.removeFromSuperlayer(); canvas = nil }
}
