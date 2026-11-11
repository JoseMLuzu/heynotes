import Foundation
import CoreGraphics
import CoreText

/// Vector paper drawing shared by gallery, PencilKit background, thumbnails and PDF export.
/// All coordinates are top-left; ink remains an independent editable layer.
enum TemplateRenderer {
    private static let ink = CGColor(srgbRed: 0.17, green: 0.19, blue: 0.22, alpha: 1)
    private static let lineColor = CGColor(srgbRed: 0.78, green: 0.82, blue: 0.85, alpha: 1)
    private static let sage = CGColor(srgbRed: 0.91, green: 0.95, blue: 0.91, alpha: 1)
    private static let lavender = CGColor(srgbRed: 0.94, green: 0.92, blue: 0.97, alpha: 1)
    private static let rose = CGColor(srgbRed: 0.98, green: 0.92, blue: 0.92, alpha: 1)

    static func draw(_ template: PaperTemplate, size: CGSize, in context: CGContext) {
        guard size.width > 0, size.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(origin: .zero, size: size))
        if template == .blank { return }
        if template == .ruled || template == .grid {
            // Legacy templates retain exactly their original 32/24-point spacing.
            ruled(in: CGRect(origin: .zero, size: size), spacing: template == .grid ? 24 : 32, context: context)
            if template == .grid {
                for x in stride(from: CGFloat(24), to: size.width, by: 24) { line(x, 0, x, size.height, context) }
            }
            return
        }
        let scale = min(size.width / 768, size.height / 480)
        context.scaleBy(x: scale, y: scale)
        let width: CGFloat = 768
        let height = min(1800, size.height / scale)
        switch template {
        case .blank, .ruled, .grid: break
        case .dotted:
            context.setFillColor(lineColor)
            for y in stride(from: CGFloat(24), to: height, by: 24) {
                for x in stride(from: CGFloat(24), to: width, by: 24) { context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)) }
            }
        case .isometric:
            for x in stride(from: -height * 2, through: width + height * 2, by: 32) {
                line(x, 0, x + height / sqrt(3), height, context)
                line(x, 0, x - height / sqrt(3), height, context)
            }
            for y in stride(from: CGFloat(32 * sqrt(3) / 2), to: height, by: 32 * sqrt(3) / 2) { line(0, y, width, y, context) }
        case .music:
            heading("Music Notes", context)
            for y in stride(from: CGFloat(120), to: height - 80, by: 110) {
                for index in 0..<5 { line(40, y + CGFloat(index) * 12, 728, y + CGFloat(index) * 12, context) }
            }
        case .lecture:
            heading(template.title, context); fields(["Subject", "Date"], y: 90, context)
            ruled(in: CGRect(x: 40, y: 130, width: 688, height: height - 170), spacing: 30, context: context)
        case .cornell:
            heading(template.title, context); fields(["Subject", "Date"], y: 90, context)
            let bottom = height * 0.75
            box(CGRect(x: 40, y: 126, width: 160, height: bottom - 126), label: "Cues", tint: lavender, context)
            box(CGRect(x: 216, y: 126, width: 512, height: bottom - 126), label: "Notes", tint: sage, context)
            ruled(in: CGRect(x: 230, y: 162, width: 484, height: bottom - 180), spacing: 28, context: context)
            box(CGRect(x: 40, y: bottom + 20, width: 688, height: height - bottom - 60), label: "Summary", tint: lavender, context)
        case .flashcardSheet:
            heading(template.title, context)
            text("Write a question above and its answer below.", x: 40, y: 84, size: 12, context)
            let cardHeight = (height - 164) / 2
            for row in 0..<2 { for column in 0..<2 {
                let rect = CGRect(x: 40 + CGFloat(column) * 352, y: 120 + CGFloat(row) * (cardHeight + 16), width: 336, height: cardHeight)
                box(rect, label: "Question", tint: (row + column) % 2 == 0 ? lavender : rose, context)
                line(rect.minX + 12, rect.minY + rect.height * 0.4, rect.maxX - 12, rect.minY + rect.height * 0.4, context)
                text("Answer", x: rect.minX + 14, y: rect.minY + rect.height * 0.4 + 16, size: 11, context)
            } }
        case .studyPlan:
            heading(template.title, context); fields(["Subject", "Exam date"], y: 90, context)
            table(["Topic", "Goal", "Review date", "Done"], rect: CGRect(x: 40, y: 126, width: 688, height: height - 180), rows: 12, context)
        case .dailyPlanner:
            heading(template.title, context); fields(["Date"], y: 90, context)
            box(CGRect(x: 40, y: 126, width: 400, height: height - 166), label: "Schedule", tint: sage, context)
            let rowHeight = (height - 210) / 15
            for index in 0..<15 {
                let y = 166 + CGFloat(index) * rowHeight
                text(String(format: "%02d:00", 7 + index), x: 52, y: y, size: 10, context)
                line(100, y + 8, 424, y + 8, context)
            }
            box(CGRect(x: 456, y: 126, width: 272, height: (height - 182) * 0.4), label: "Priorities", tint: rose, context)
            box(CGRect(x: 456, y: 142 + (height - 182) * 0.4, width: 272, height: (height - 182) * 0.6), label: "Notes", tint: lavender, context)
        case .weeklyPlanner:
            heading(template.title, context); fields(["Week of"], y: 90, context)
            let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let bottom = height * 0.76
            for (index, day) in days.enumerated() {
                let rect = CGRect(x: 40 + CGFloat(index) * 100, y: 126, width: 88, height: bottom - 126)
                box(rect, label: day, tint: index > 4 ? rose : lavender, context)
                ruled(in: CGRect(x: rect.minX + 8, y: 164, width: 72, height: bottom - 180), spacing: 28, context: context)
            }
            box(CGRect(x: 40, y: bottom + 20, width: 688, height: height - bottom - 60), label: "Notes & intentions", tint: sage, context)
        case .monthlyCalendar:
            heading("Monthly Calendar", context); fields(["Month", "Year"], y: 90, context)
            let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            for (index, day) in days.enumerated() { text(day, x: 50 + CGFloat(index) * (688 / 7), y: 130, size: 12, bold: true, context) }
            table(Array(repeating: "", count: 7), rect: CGRect(x: 40, y: 148, width: 688, height: height - 188), rows: 6, header: false, context)
        case .todo:
            heading(template.title, context); fields(["Date"], y: 90, context)
            for y in stride(from: CGFloat(144), to: height - 40, by: 36) {
                outline(CGRect(x: 44, y: y - 8, width: 12, height: 12), context)
                line(72, y + 4, 728, y + 4, context)
            }
        case .kanban:
            heading(template.title, context)
            for (index, name) in ["To Do", "Doing", "Done"].enumerated() {
                let rect = CGRect(x: 40 + CGFloat(index) * 234, y: 108, width: 220, height: height - 148)
                box(rect, label: name, tint: [rose, lavender, sage][index], context)
                ruled(in: CGRect(x: rect.minX + 12, y: 156, width: 196, height: height - 214), spacing: 64, context: context)
            }
        case .habitTracker:
            heading(template.title, context); fields(["Month"], y: 90, context)
            let left: CGFloat = 188, cell = (728 - left) / 31, bottom = height - 156
            text("Habit", x: 48, y: 134, size: 12, bold: true, context)
            for day in 0..<31 {
                let x = left + CGFloat(day) * cell
                text(String(day + 1), x: x + 3, y: 134, size: 8, context)
                line(x, 148, x, bottom, context)
            }
            for row in 0...8 { line(40, 148 + CGFloat(row) * (bottom - 148) / 8, 728, 148 + CGFloat(row) * (bottom - 148) / 8, context) }
            box(CGRect(x: 40, y: bottom + 20, width: 688, height: 96), label: "Notes", tint: sage, context)
        }
    }

    private static func heading(_ title: String, _ c: CGContext) { text(title, x: 40, y: 52, size: 24, bold: true, c) }
    private static func fields(_ labels: [String], y: CGFloat, _ c: CGContext) {
        let width = 688 / CGFloat(labels.count)
        for (index, label) in labels.enumerated() {
            let x = 40 + CGFloat(index) * width
            text(label + ":", x: x, y: y, size: 11, c)
            line(x + 76, y + 4, x + width - 16, y + 4, c)
        }
    }
    private static func table(_ titles: [String], rect: CGRect, rows: Int, header: Bool = true, _ c: CGContext) {
        let headerHeight: CGFloat = header ? 30 : 0
        if header { c.setFillColor(lavender); c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)) }
        let columnWidth = rect.width / CGFloat(titles.count)
        for (index, title) in titles.enumerated() {
            let x = rect.minX + CGFloat(index) * columnWidth
            line(x, rect.minY, x, rect.maxY, c)
            if header { text(title, x: x + 8, y: rect.minY + 20, size: 11, bold: true, c) }
        }
        line(rect.maxX, rect.minY, rect.maxX, rect.maxY, c)
        line(rect.minX, rect.minY, rect.maxX, rect.minY, c)
        for row in 0...rows {
            let y = rect.minY + headerHeight + CGFloat(row) * (rect.height - headerHeight) / CGFloat(rows)
            line(rect.minX, y, rect.maxX, y, c)
        }
    }
    private static func box(_ rect: CGRect, label: String, tint: CGColor, _ c: CGContext) {
        c.setFillColor(tint); c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 30))
        outline(rect, c)
        text(label, x: rect.minX + 12, y: rect.minY + 21, size: 12, bold: true, c)
    }
    private static func outline(_ rect: CGRect, _ c: CGContext) { c.setStrokeColor(lineColor); c.setLineWidth(0.7); c.stroke(rect) }
    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ c: CGContext) {
        c.setStrokeColor(lineColor); c.setLineWidth(0.5)
        c.move(to: CGPoint(x: x1, y: y1)); c.addLine(to: CGPoint(x: x2, y: y2)); c.strokePath()
    }
    private static func ruled(in rect: CGRect, spacing: CGFloat, context c: CGContext) {
        for y in stride(from: rect.minY + spacing, to: rect.maxY, by: spacing) { line(rect.minX, y, rect.maxX, y, c) }
    }
    private static func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false, _ c: CGContext) {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let font = bold ? CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base : base
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink] as CFDictionary
        let string = CFAttributedStringCreate(nil, value as CFString, attributes)!
        let line = CTLineCreateWithAttributedString(string)
        c.saveGState(); c.translateBy(x: x, y: y); c.scaleBy(x: 1, y: -1)
        c.textMatrix = .identity; c.textPosition = .zero
        CTLineDraw(line, c); c.restoreGState()
    }
}
