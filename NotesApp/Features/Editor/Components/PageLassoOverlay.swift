import UIKit
import PencilKit

private struct LassoPreview: Sendable {
    var selection: PageLassoSelection
    let remainingInk: UIImage?
    let remainingRect: CGRect
    let selectedInk: UIImage?
    var selectedRect: CGRect

    static func make(_ selection: PageLassoSelection, size: CGSize) throws -> Self {
        let strokes = selection.drawing.strokes
        let selected = PKDrawing(strokes: strokes.enumerated().compactMap { selection.strokeIndices.contains($0.offset) ? $0.element : nil })
        let remaining = PKDrawing(strokes: strokes.enumerated().compactMap { selection.strokeIndices.contains($0.offset) ? nil : $0.element })
        let scale = min(2, 2400 / max(size.width, size.height))
        try Task.checkCancellation()
        var selectedImage: UIImage?, remainingImage: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            selectedImage = selected.strokes.isEmpty ? nil : selected.image(from: selected.bounds, scale: scale)
            remainingImage = remaining.strokes.isEmpty ? nil : remaining.image(from: remaining.bounds, scale: scale)
        }
        try Task.checkCancellation()
        return Self(selection: selection, remainingInk: remainingImage, remainingRect: remaining.bounds,
                    selectedInk: selectedImage, selectedRect: selected.bounds)
    }
}

/// Selection previews never mutate the real PKDrawing or document objects. A background
/// flush during a cancelled/unfinished drag therefore saves the last committed page.
final class PageLassoOverlay: UIView, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    weak var canvas: InkCanvas?
    weak var content: PageObjectsContentView?
    var onActivity: ((Bool) -> Void)?
    var onCommit: ((PageLassoSelection, PKDrawing, [PageElement], String) -> Bool)?
    var active = false { didSet { if active != oldValue { reset(); configure() } } }
    var fingerDrawing = false
    var zoom: CGFloat = 1
    private(set) var isTracking = false
    var selection: PageLassoSelection? { preview?.selection }
    private var elements: [PageElement] = []
    private var images: [String: UIImage] = [:]
    private var preview: LassoPreview?
    private var points: [CGPoint] = []
    private var delta = CGPoint.zero
    private var moving = false
    private var lastTouch = UITouch.TouchType.pencil
    private var generation = 0
    private var worker: Task<LassoPreview?, Error>?
    private var completion: Task<Void, Never>?
    private let textLayouts = PageTextLayoutCache()
    private let pan = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private lazy var menu = UIEditMenuInteraction(delegate: self)

    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear; isOpaque = false
        pan.addTarget(self, action: #selector(drag(_:))); pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue), NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.delegate = self; addGestureRecognizer(pan)
        tap.addTarget(self, action: #selector(tapped(_:))); tap.allowedTouchTypes = pan.allowedTouchTypes
        tap.require(toFail: pan); addGestureRecognizer(tap)
        addInteraction(menu)
        NotificationCenter.default.addObserver(self, selector: #selector(reset), name: UIApplication.willResignActiveNotification, object: nil)
        configure()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { reset() } }
    func yieldFingerGestures(to pagePan: UIGestureRecognizer) { pan.require(toFail: pagePan); tap.require(toFail: pagePan) }
    func fingerDragEditsSelection(at point: CGPoint) -> Bool {
        active && selection?.bounds.insetBy(dx: -8 / max(zoom, 0.1), dy: -8 / max(zoom, 0.1)).contains(point) == true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === pan { lastTouch = touch.type }; return true
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, lastTouch == .direct, !fingerDrawing else { return active }
        let location = pan.location(in: self), translation = pan.translation(in: self)
        return fingerDragEditsSelection(at: CGPoint(x: location.x - translation.x, y: location.y - translation.y))
    }
    func update(elements: [PageElement], images: [String: UIImage]) {
        self.elements = elements; self.images = images
        if let selection, selection.drawing != canvas?.drawing || selection.elements != elements { reset() }
        refreshPresentation()
    }
    private func configure() { pan.isEnabled = active; tap.isEnabled = active; isHidden = !active }
    @objc func reset() {
        generation += 1; worker?.cancel(); completion?.cancel(); worker = nil; completion = nil
        menu.dismissMenu(); preview = nil; points = []; delta = .zero; moving = false
        isTracking = false; onActivity?(false); refreshPresentation()
    }
    func select(points: [CGPoint]) {
        reset()
        guard active, let canvas else { return }
        let drawing = canvas.drawing, objects = elements, token = generation, size = bounds.size
        let pageID = canvas.pageID, tolerance = 3 / max(zoom, 0.1)
        self.points = points; setNeedsDisplay()
        isTracking = true; onActivity?(true)
        let task = Task.detached(priority: .userInitiated) {
            guard let selection = try PageLassoSelection.select(points: points, drawing: drawing, elements: objects, tolerance: tolerance) else { return nil as LassoPreview? }
            return try LassoPreview.make(selection, size: size)
        }
        worker = task
        completion = Task { [weak self] in
            do {
                let result = try await task.value
                guard let self, self.generation == token else { return }
                guard self.active, !Task.isCancelled, self.canvas?.pageID == pageID,
                      self.canvas?.drawing == drawing, self.elements == objects else { self.reset(); return }
                self.preview = result; self.points = []; self.isTracking = false; self.onActivity?(false)
                self.worker = nil; self.completion = nil; self.refreshPresentation()
            } catch {
                guard let self, self.generation == token else { return }; self.reset()
            }
        }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if fingerDragEditsSelection(at: point) { menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point)) }
        else {
            let r = 6 / max(zoom, 0.1)
            select(points: [CGPoint(x: point.x - r, y: point.y - r), CGPoint(x: point.x + r, y: point.y - r),
                            CGPoint(x: point.x + r, y: point.y + r), CGPoint(x: point.x - r, y: point.y + r)])
        }
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self), translation = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            menu.dismissMenu()
            let start = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            moving = fingerDragEditsSelection(at: start)
            if !moving { reset(); points = [start, point] }
            isTracking = true; onActivity?(true)
            if moving { delta = selection?.clamped(translation, pageSize: bounds.size) ?? .zero }
            setNeedsDisplay()
        case .changed:
            if moving { delta = selection?.clamped(translation, pageSize: bounds.size) ?? .zero }
            else if points.count < 4096 { points.append(point) }
            setNeedsDisplay()
        case .ended:
            if moving { finishMove(translation) }
            else { let loop = points + [point]; select(points: loop) }
        case .cancelled, .failed: reset()
        default: break
        }
    }
    func finishMove(_ translation: CGPoint) {
        guard var preview else { reset(); return }
        let offset = preview.selection.clamped(translation, pageSize: bounds.size)
        if offset != .zero {
            let change = preview.selection.moving(by: offset)
            guard onCommit?(preview.selection, change.drawing, change.elements, "Move Selection") == true else { reset(); return }
            let previous = preview.selection
            preview.selection = PageLassoSelection(drawing: change.drawing, elements: change.elements, strokeIndices: previous.strokeIndices,
                elementIDs: previous.elementIDs, bounds: previous.bounds.offsetBy(dx: offset.x, dy: offset.y),
                movementBounds: previous.movementBounds.offsetBy(dx: offset.x, dy: offset.y))
            preview.selectedRect = preview.selectedRect.offsetBy(dx: offset.x, dy: offset.y)
            elements = change.elements; self.preview = preview
        }
        delta = .zero; moving = false; isTracking = false; onActivity?(false); refreshPresentation()
    }
    func deleteSelection() {
        guard let selection else { return }
        let change = selection.deleting()
        if onCommit?(selection, change.drawing, change.elements, "Delete Selection") == true { elements = change.elements }
        reset()
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard selection != nil else { return nil }
        return UIMenu(children: [UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteSelection() },
                                UIAction(title: "Deselect") { [weak self] _ in self?.reset() }])
    }
    private func refreshPresentation() {
        canvas?.alpha = preview == nil ? 1 : 0
        content?.elements = active ? elements.filter { selection?.elementIDs.contains($0.id) != true } : elements
        isAccessibilityElement = selection != nil
        accessibilityLabel = "Lasso selection"
        accessibilityValue = selection.map { "\($0.strokeIndices.count) strokes and \($0.elementIDs.count) objects" }
        accessibilityCustomActions = selection == nil ? nil : [UIAccessibilityCustomAction(name: "Delete selection", actionHandler: { [weak self] _ in self?.deleteSelection(); return true }),
                                                               UIAccessibilityCustomAction(name: "Deselect", actionHandler: { [weak self] _ in self?.reset(); return true })]
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard active, let context = UIGraphicsGetCurrentContext() else { return }
        if let preview {
            preview.remainingInk?.draw(in: preview.remainingRect)
            let selected = preview.selection.elements.filter { preview.selection.elementIDs.contains($0.id) }.map { original in
                var item = original; item.x += delta.x; item.y += delta.y; return item
            }
            PageElementRenderer.draw(elements.filter { $0.kind == .tape && !preview.selection.elementIDs.contains($0.id) }, images: [:], in: context)
            PageElementRenderer.draw(selected.filter { $0.kind != .tape }, images: images, textLayouts: textLayouts, in: context)
            preview.selectedInk?.draw(in: preview.selectedRect.offsetBy(dx: delta.x, dy: delta.y))
            PageElementRenderer.draw(selected.filter { $0.kind == .tape }, images: [:], in: context)
            context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(1.5 / max(zoom, 0.1))
            context.setLineDash(phase: 0, lengths: [5 / max(zoom, 0.1), 3 / max(zoom, 0.1)])
            context.stroke(preview.selection.bounds.offsetBy(dx: delta.x, dy: delta.y).insetBy(dx: -3, dy: -3))
        } else { PageElementRenderer.draw(elements.filter { $0.kind == .tape }, images: [:], in: context) }
        if points.count > 1 {
            context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(1.5 / max(zoom, 0.1))
            context.setLineDash(phase: 0, lengths: [5 / max(zoom, 0.1), 3 / max(zoom, 0.1)])
            context.addLines(between: points); context.strokePath()
        }
    }
    deinit { worker?.cancel(); completion?.cancel() }
}
