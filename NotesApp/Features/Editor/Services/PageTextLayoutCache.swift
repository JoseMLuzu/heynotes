import Foundation
import CoreText

/// One cache per canvas content view, confined to that view's drawing thread.
/// Layouts are never shared with PDF/thumbnail workers. Position is excluded from
/// the signature so dragging text reuses its typesetting while resizing invalidates it.
final class PageTextLayoutCache {
    private struct Signature: Equatable {
        let text: String
        let font: String?
        let size, width, height, red, green, blue, opacity: Double
        init(_ item: PageElement) {
            text = item.text; font = item.fontName; size = item.fontSize
            width = item.width; height = item.height
            red = item.red; green = item.green; blue = item.blue; opacity = item.opacity
        }
    }
    private final class Entry {
        let signature: Signature
        let frame: CTFrame
        init(_ signature: Signature, frame: CTFrame) { self.signature = signature; self.frame = frame }
    }
    private let entries = NSCache<NSUUID, Entry>()
    private(set) var builds = 0
    private(set) var hits = 0
    init() { entries.countLimit = 64 }

    func frame(for item: PageElement) -> CTFrame {
        let signature = Signature(item), key = item.id as NSUUID
        if let cached = entries.object(forKey: key), cached.signature == signature {
            hits += 1; return cached.frame
        }
        let frame = PageElementRenderer.textFrame(for: item)
        entries.setObject(Entry(signature, frame: frame), forKey: key)
        builds += 1
        return frame
    }
}
