import UIKit
import PencilKit
import CoreText

struct HandwritingLayoutOptions: Sendable {
    var alignToPaper = true
    var sizeScale = 1.0
    var baselineOffset = 0.0
}

/// Measures actual glyph paths and Core Text's first baseline instead of guessing a
/// text rectangle from total ink height. Each recognized line keeps its page position.
enum HandwritingTextLayout {
    struct Conversion {
        var item: PageElement
        let ink: PKDrawing
    }

    static func make(lines: [RecognizedHandwritingLine], source: PKDrawing, pageSize: CGSize,
                     template: PaperTemplate?, fontName: String, fontPath: String?,
                     options: HandwritingLayoutOptions) -> [Conversion]? {
        guard !lines.isEmpty, lines.count <= 12 else { return nil }
        var groups = Array(repeating: [PKStroke](), count: lines.count)
        for stroke in source.strokes {
            let center = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
            guard let index = lines.indices.min(by: {
                distance(center, to: lines[$0].bounds) < distance(center, to: lines[$1].bounds)
            }) else { return nil }
            groups[index].append(stroke)
        }
        var conversions: [Conversion] = []
        for (index, line) in lines.enumerated() {
            guard !groups[index].isEmpty else { return nil }
            let ink = lines.count == 1 ? source : PKDrawing(strokes: groups[index])
            // Native strokes give tighter ink bounds than OCR's padded detection region.
            guard let item = layout(text: line.text, inkBounds: ink.bounds, size: pageSize,
                                    template: template, fontName: fontName, options: options) else { return nil }
            var configured = item; configured.fontFilePath = fontPath
            configured.originalInkAnchorX = configured.x; configured.originalInkAnchorY = configured.y
            if let color = ink.strokes.first?.ink.color {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                    configured.red = r; configured.green = g; configured.blue = b
                }
            }
            conversions.append(Conversion(item: configured, ink: ink))
        }
        return conversions
    }

    private static func layout(text: String, inkBounds: CGRect, size: CGSize, template: PaperTemplate?,
                               fontName: String, options: HandwritingLayoutOptions) -> PageElement? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("\n"),
              !inkBounds.isNull, inkBounds.minX >= 0, inkBounds.minY >= 0 else { return nil }
        func measured(_ pointSize: CGFloat) -> (UIFont, CTLine, CGRect, CGFloat) {
            let font = HandwritingFont.resolve(fontName, size: pointSize)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            return (font, line, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds), CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        let reference = measured(24)
        let scale = min(1.3, max(0.7, options.sizeScale.isFinite ? options.sizeScale : 1))
        var pointSize = min(72, max(12, inkBounds.height * 24 / max(1, reference.2.height) * scale))
        var metrics = measured(pointSize)
        let estimate = inkBounds.maxY + metrics.2.minY
        let guide = options.alignToPaper ? writingGuide(near: CGPoint(x: inkBounds.midX, y: estimate), template: template, size: size) : nil
        if let guide, metrics.2.height > guide.spacing * 0.88 {
            pointSize = max(12, pointSize * guide.spacing * 0.88 / metrics.2.height)
            metrics = measured(pointSize)
        }
        let x = max(0, inkBounds.minX - metrics.2.minX)
        let available = size.width - x
        guard available > 4 else { return nil }
        let textWidth = max(metrics.3, metrics.2.maxX)
        if textWidth + 4 > available {
            let fitted = pointSize * (available - 4) / max(1, textWidth)
            guard fitted >= 12 else { return nil }
            pointSize = fitted; metrics = measured(pointSize)
        }
        var item = PageElement(kind: .text, rect: CGRect(x: x, y: 0,
            width: min(available, ceil(max(metrics.3, metrics.2.maxX) + 4)), height: ceil(metrics.0.lineHeight + 8)))
        item.text = text; item.fontName = fontName; item.fontSize = pointSize
        let frame = PageElementRenderer.textFrame(for: item)
        guard CFArrayGetCount(CTFrameGetLines(frame)) == 1 else { return nil }
        var origin = CGPoint.zero
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 1), &origin)
        let rawBaseline = inkBounds.maxY + metrics.2.minY
        let target = (guide?.y ?? rawBaseline) + min(8, max(-8, options.baselineOffset.isFinite ? options.baselineOffset : 0))
        item.y = target - (item.height - origin.y)
        guard item.y >= 0, item.rect.maxY <= size.height, item.rect.maxX <= size.width else { return nil }
        return item
    }

    /// Matches TemplateRenderer's logical lines. PDF backgrounds and non-writing regions
    /// have no guide; they retain the measured ink position rather than guessing a grid.
    static func writingGuide(near point: CGPoint, template: PaperTemplate?, size: CGSize) -> (y: CGFloat, spacing: CGFloat)? {
        guard let template else { return nil }
        let scale = min(size.width / 768, size.height / 480)
        let height = min(1800, size.height / scale)
        let region: CGRect, spacing: CGFloat
        switch template {
        case .ruled, .grid:
            spacing = template == .ruled ? 32 : 24; region = CGRect(origin: .zero, size: size)
        case .dotted:
            spacing = 24 * scale; region = CGRect(x: 0, y: 0, width: 768 * scale, height: height * scale)
        case .lecture:
            spacing = 30 * scale; region = CGRect(x: 40 * scale, y: 130 * scale, width: 688 * scale, height: (height - 170) * scale)
        case .cornell:
            spacing = 28 * scale; region = CGRect(x: 230 * scale, y: 162 * scale, width: 484 * scale, height: (height * 0.75 - 180) * scale)
        default: return nil
        }
        guard region.contains(point), spacing > 0 else { return nil }
        let index = ((point.y - region.minY) / spacing).rounded()
        let y = region.minY + index * spacing
        guard index >= 1, y < region.maxY, abs(y - point.y) <= spacing * 0.45 else { return nil }
        return (y, spacing)
    }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
