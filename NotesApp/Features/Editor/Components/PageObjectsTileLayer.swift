import UIKit
import QuartzCore

/// CATiledLayer calls draw on background threads. It receives immutable page values,
/// never a UIView or SwiftData model. Cache access is serialized separately from updates.
private final class TiledObjectSource: @unchecked Sendable {
    private struct Snapshot {
        let elements: [PageElement]
        let images: [String: UIImage]
    }
    private let stateLock = NSLock(), drawingLock = NSLock()
    private var snapshot = Snapshot(elements: [], images: [:])
    private let layouts = PageTextLayoutCache()

    func update(elements: [PageElement], images: [String: UIImage]) {
        stateLock.lock(); snapshot = Snapshot(elements: elements, images: images); stateLock.unlock()
    }
    func draw(in context: CGContext) {
        stateLock.lock(); let value = snapshot; stateLock.unlock()
        let clip = context.boundingBoxOfClipPath.insetBy(dx: -2, dy: -2)
        let visible = value.elements.filter {
            let padding = max(12, $0.lineWidth * 4)
            return $0.kind != .tape && $0.visibleRect.insetBy(dx: -padding, dy: -padding).intersects(clip)
        }
        drawingLock.lock(); defer { drawingLock.unlock() }
        PageElementRenderer.draw(visible, images: value.images, textLayouts: layouts, in: context)
    }
}

/// Redraw only visible tiles at the current transform's resolution. Increasing a
/// full-page bitmap's contentsScale instead could allocate hundreds of megabytes.
final class PageObjectsTileLayer: CATiledLayer, @unchecked Sendable {
    private let source: TiledObjectSource
    override init() { source = TiledObjectSource(); super.init(); configure() }
    override init(layer: Any) {
        source = (layer as? PageObjectsTileLayer)?.source ?? TiledObjectSource()
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { source = TiledObjectSource(); super.init(coder: coder); configure() }
    private func configure() {
        tileSize = CGSize(width: 512, height: 512)
        levelsOfDetail = 1; levelsOfDetailBias = 3
        isOpaque = false
    }
    override class func fadeDuration() -> CFTimeInterval { 0 }
    func update(elements: [PageElement], images: [String: UIImage]) { source.update(elements: elements, images: images); setNeedsDisplay() }
    override func draw(in ctx: CGContext) { source.draw(in: ctx) }
}
