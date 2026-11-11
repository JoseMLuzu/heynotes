import UIKit

final class PageObjectsContentView: UIView {
    private let textLayouts = PageTextLayoutCache()
    var elements: [PageElement] = [] { didSet { if oldValue != elements { setNeedsDisplay() } } }
    var images: [String: UIImage] = [:] {
        didSet {
            if oldValue.count != images.count || images.contains(where: { oldValue[$0.key] !== $0.value }) { setNeedsDisplay() }
        }
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PageElementRenderer.draw(elements.filter { $0.kind != .tape }, images: images, textLayouts: textLayouts, in: context)
    }
}

/// Tape sits over ink; the other inserted objects sit below ink. Only explicit object tools
/// capture the full page. In writing mode, Pencil always passes through to PencilKit.
final class PageObjectsInteractionView: UIView {
    var elements: [PageElement] = [] { didSet { if oldValue != elements { setNeedsDisplay(); updateAccessibility() } } }
    var revealed: Set<UUID> = [] { didSet { if oldValue != revealed { setNeedsDisplay() } } }
    var selectedID: UUID? { didSet { if oldValue != selectedID { setNeedsDisplay() } } }
    var tool: EditorTool = .pen {
        didSet {
            if oldValue != tool {
                configureInput()
                if oldValue == .objects || tool == .objects { setNeedsDisplay() }
            }
        }
    }
    var fingerDrawing = false { didSet { if oldValue != fingerDrawing { configureInput() } } }
    private weak var objectPan: UIPanGestureRecognizer?
    private weak var objectTap: UITapGestureRecognizer?
    var style = InkStyle()
    var zoom: CGFloat = 1 { didSet { if oldValue != zoom, tool == .objects { setNeedsDisplay() } } }
    var onCommit: ((PageElement, Bool) -> Bool)?
    var onPreview: (([PageElement]) -> Void)?
    var onSelect: ((UUID?) -> Void)?
    var onReveal: ((UUID) -> Void)?
    private var original: PageElement?
    private var draft: PageElement?
    private var start = CGPoint.zero
    private var resizing = false
    private var creating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        objectPan = pan; pan.isEnabled = false
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        objectTap = tap
        tap.allowedTouchTypes = pan.allowedTouchTypes
        tap.require(toFail: pan); addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func configureInput() {
        objectPan?.isEnabled = tool.editsObjects
        // Pencil creates shapes; the finger remains available for page navigation.
        // Selection still allows dragging existing objects directly with a finger.
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let direct = NSNumber(value: UITouch.TouchType.direct.rawValue)
        let touches = tool.elementKind != nil && !fingerDrawing ? [pencil] : [pencil, direct]
        objectPan?.allowedTouchTypes = touches
        objectTap?.allowedTouchTypes = touches
    }
    func yieldFingerGestures(to pagePan: UIGestureRecognizer) {
        objectPan?.require(toFail: pagePan)
        objectTap?.require(toFail: pagePan)
    }
    func fingerDragEditsObject(at point: CGPoint) -> Bool {
        tool == .objects && elements.contains {
            $0.rect.insetBy(dx: -12 / max(zoom, 0.01), dy: -12 / max(zoom, 0.01)).contains(point)
        }
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard bounds.contains(point) else { return false }
        if tool.editsObjects { return true }
        if event?.allTouches?.contains(where: { $0.type == .pencil }) == true { return false }
        return elements.contains { $0.kind == .tape && $0.rect.contains(point) }
    }
    private var display: [PageElement] {
        guard let draft else { return elements }
        if creating { return elements + [draft] }
        return elements.map { $0.id == draft.id ? draft : $0 }
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PageElementRenderer.draw(display.filter { $0.kind == .tape }, images: [:], revealed: revealed, in: context)
        if tool == .objects, let selected = display.first(where: { $0.id == selectedID }) {
            context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(1.5 / max(zoom, 0.01))
            context.stroke(selected.rect)
            let side = 10 / max(zoom, 0.01)
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.fillEllipse(in: CGRect(x: selected.rect.maxX - side / 2, y: selected.rect.maxY - side / 2, width: side, height: side))
        }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let item = elements.reversed().first { $0.rect.contains(point) && (tool.editsObjects || $0.kind == .tape) }
        if tool == .objects { onSelect?(item?.id) }
        else if let kind = tool.elementKind {
            let rect = CGRect(x: min(max(0, point.x - 80), max(0, bounds.width - 160)), y: min(max(0, point.y - 20), max(0, bounds.height - 40)), width: min(160, bounds.width), height: 40)
            let item = newElement(kind, rect: rect)
            if onCommit?(item, true) == true { elements.append(item) }
        } else if item?.kind == .tape, let id = item?.id { onReveal?(id) }
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard tool.editsObjects else { return }
        let point = gesture.location(in: self), delta = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            start = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
            creating = tool.elementKind != nil
            if let kind = tool.elementKind { draft = newElement(kind, rect: CGRect(x: start.x, y: start.y, width: 1, height: 1)) }
            else {
                original = elements.reversed().first { $0.rect.insetBy(dx: -12 / max(zoom, 0.01), dy: -12 / max(zoom, 0.01)).contains(start) }
                draft = original
                selectedID = original?.id; onSelect?(original?.id)
                if let original { resizing = hypot(start.x - original.rect.maxX, start.y - original.rect.maxY) < 24 / max(zoom, 0.01) }
            }
            updateDraft(point: point, delta: delta)
        case .changed: updateDraft(point: point, delta: delta)
        case .ended:
            if let draft, max(draft.width, draft.height) >= 8, onCommit?(draft, creating) == true {
                if creating { elements.append(draft) } else { elements = elements.map { $0.id == draft.id ? draft : $0 } }
            }
            clearDraft()
        case .cancelled, .failed: clearDraft()
        default: break
        }
    }
    private func updateDraft(point: CGPoint, delta: CGPoint) {
        guard var item = draft else { return }
        if creating {
            let end = CGPoint(x: min(bounds.width, max(0, point.x)), y: min(bounds.height, max(0, point.y)))
            item.x = max(0, min(start.x, end.x)); item.y = max(0, min(start.y, end.y))
            item.width = max(1, abs(end.x - start.x)); item.height = max(1, abs(end.y - start.y))
            item.reversed = (end.x - start.x) * (end.y - start.y) < 0
        } else if let original {
            if resizing {
                item.width = max(16, min(bounds.width - original.x, original.width + delta.x))
                item.height = max(16, min(bounds.height - original.y, original.height + delta.y))
            } else {
                item.x = min(max(0, original.x + delta.x), max(0, bounds.width - item.width))
                item.y = min(max(0, original.y + delta.y), max(0, bounds.height - item.height))
            }
        }
        draft = item; onPreview?(display); setNeedsDisplay()
    }
    private func clearDraft() { draft = nil; original = nil; onPreview?(elements); setNeedsDisplay() }
    private func newElement(_ kind: PageElementKind, rect: CGRect) -> PageElement {
        var item = PageElement(kind: kind, rect: rect)
        item.red = style.red; item.green = style.green; item.blue = style.blue
        item.lineWidth = style.width; item.opacity = style.opacity
        return item
    }
    private func updateAccessibility() {
        accessibilityElements = elements.map { item in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = item.kind == .text ? item.text : item.kind.title
            element.accessibilityFrameInContainerSpace = item.rect
            element.accessibilityTraits = .button
            element.accessibilityCustomActions = [UIAccessibilityCustomAction(name: item.kind == .tape ? "Reveal or cover" : "Select for editing", actionHandler: { [weak self] _ in
                if item.kind == .tape { self?.onReveal?(item.id) } else { self?.onSelect?(item.id) }
                return true
            })]
            return element
        }
    }
}
