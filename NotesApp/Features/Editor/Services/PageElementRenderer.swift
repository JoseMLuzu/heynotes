import UIKit
import CoreText

enum PageElementRenderer {
    static func draw(_ elements: [PageElement], images: [String: UIImage], revealed: Set<UUID> = [],
                     textLayouts: PageTextLayoutCache? = nil, in context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        UIGraphicsPushContext(context); defer { UIGraphicsPopContext() }
        for item in elements {
            context.saveGState()
            let rect = item.rect
            let color = CGColor(red: item.red, green: item.green, blue: item.blue, alpha: item.opacity)
            context.setStrokeColor(color); context.setFillColor(color)
            context.setLineWidth(item.lineWidth); context.setLineCap(.round); context.setLineJoin(.round)
            switch item.kind {
            case .image:
                if let path = item.imagePath { images[path]?.draw(in: rect) }
            case .text:
                let frame = textLayouts?.frame(for: item) ?? textFrame(for: item)
                context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                CTFrameDraw(frame, context)
            case .rectangle: context.stroke(rect)
            case .ellipse: context.strokeEllipse(in: rect)
            case .line, .arrow:
                let start = CGPoint(x: rect.minX, y: item.reversed ? rect.maxY : rect.minY)
                let end = CGPoint(x: rect.maxX, y: item.reversed ? rect.minY : rect.maxY)
                context.move(to: start); context.addLine(to: end)
                if item.kind == .arrow {
                    let angle = atan2(end.y - start.y, end.x - start.x), length = max(12, item.lineWidth * 4)
                    for delta in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                        context.move(to: end)
                        context.addLine(to: CGPoint(x: end.x - length * cos(angle + delta), y: end.y - length * sin(angle + delta)))
                    }
                }
                context.strokePath()
            case .tape:
                let open = revealed.contains(item.id)
                context.setFillColor(UIColor(red: 0.94, green: 0.88, blue: 0.65, alpha: open ? 0.08 : 1).cgColor)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 5).cgPath
                context.addPath(path); context.fillPath()
                context.setLineWidth(1)
                context.setStrokeColor(UIColor(red: 0.60, green: 0.51, blue: 0.25, alpha: 0.65).cgColor)
                if open { context.setLineDash(phase: 0, lengths: [4, 3]) }
                context.addPath(path); context.strokePath()
            }
            context.restoreGState()
        }
    }

    static func textFrame(for item: PageElement) -> CTFrame {
        let font: CTFont
        if let name = item.fontName, let face = UIFont(name: name, size: item.fontSize) {
            font = CTFontCreateWithName(face.fontName as CFString, item.fontSize, nil)
        } else {
            font = CTFontCreateUIFontForLanguage(.system, item.fontSize, nil)!
        }
        let string = NSAttributedString(string: item.text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: item.red, green: item.green, blue: item.blue, alpha: item.opacity)
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(origin: .zero, size: item.rect.size), transform: nil)
        return CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    }
}
