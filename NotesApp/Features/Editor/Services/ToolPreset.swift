import PencilKit
import SwiftUI

struct ToolPreset: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var tool: EditorTool
    var ink = InkStyle()
    var eraserMode: EraserMode = .strokes
    var eraserWidth: Double = 20
    var stampSymbol: StampSymbol? = nil
    var stickyStyle: StickyNoteStyle? = nil
    var lassoScope: LassoScope? = nil

    static func widthRange(for tool: EditorTool) -> ClosedRange<Double> {
        let range = (tool.inkType ?? .pen).validWidthRange
        return Double(range.lowerBound)...min(tool == .marker ? 60 : 12, Double(range.upperBound))
    }
    static var eraserRange: ClosedRange<Double> {
        let range = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        return Double(range.lowerBound)...min(100, Double(range.upperBound))
    }

    var sanitized: Self {
        var value = self
        value.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        if value.name.isEmpty { value.name = tool.title }
        value.ink.red = Self.clamp(ink.red, to: 0...1)
        value.ink.green = Self.clamp(ink.green, to: 0...1)
        value.ink.blue = Self.clamp(ink.blue, to: 0...1)
        value.ink.opacity = Self.clamp(ink.opacity, to: 0.1...1)
        value.ink.width = Self.clamp(ink.width, to: Self.widthRange(for: tool))
        value.eraserWidth = Self.clamp(eraserWidth, to: Self.eraserRange)
        return value
    }
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }
    var detail: String {
        if tool == .lasso { return (lassoScope ?? .allContent).title }
        if tool == .objects { return "Selection" }
        if tool == .tape { return "Study tape" }
        if tool == .stamp { return stampSymbol?.title ?? StampSymbol.check.title }
        if tool == .sticky { return "\((stickyStyle ?? .yellow).rawValue.capitalized) note" }
        if tool.usesAuxiliaryInput, !tool.usesInkStyle { return tool.title }
        if tool == .eraser && eraserMode == .highlighter { return "Highlighter · \(eraserWidth.formatted(.number.precision(.fractionLength(0...1)))) pt" }
        if tool == .eraser { return eraserMode == .strokes ? "Whole strokes" : "\(eraserWidth.formatted(.number.precision(.fractionLength(0...1)))) pt" }
        return "\(ink.width.formatted(.number.precision(.fractionLength(0...1)))) pt · \(Int(ink.opacity * 100))%"
    }

    static var initialFavorites: [Self] {
        [Self(name: "Blue pen", tool: .pen, ink: InkStyle(red: 0.15, green: 0.35, blue: 0.8, width: 2)),
         Self(name: "Red pen", tool: .pen, ink: InkStyle(red: 0.82, green: 0.18, blue: 0.22, width: 3)),
         Self(name: "Graphite pencil", tool: .pencil, ink: InkStyle(red: 0.35, green: 0.35, blue: 0.35, width: 2)),
         Self(name: "Yellow highlighter", tool: .marker, ink: InkStyle(red: 1, green: 0.78, blue: 0.15, width: 18, opacity: 0.55)),
         Self(name: "Precise eraser", tool: .eraser, eraserMode: .precise)].map(\.sanitized)
    }
}

extension ToolPreferences {
    func capturePreset(for tool: EditorTool? = nil, name: String? = nil) -> ToolPreset {
        let tool = tool ?? selected
        return ToolPreset(name: name ?? tool.title, tool: tool, ink: inkStyle(for: tool), eraserMode: eraserMode, eraserWidth: eraserWidth,
                          stampSymbol: tool == .stamp ? stampSymbol : nil, stickyStyle: tool == .sticky ? stickyStyle : nil,
                          lassoScope: tool == .lasso ? lassoScope : nil).sanitized
    }
    func apply(_ preset: ToolPreset) {
        let preset = preset.sanitized
        selected = preset.tool
        if selected.usesInkStyle { ink = preset.ink }
        else if selected == .eraser { eraserMode = preset.eraserMode; eraserWidth = preset.eraserWidth }
        if selected == .stamp { stampSymbol = preset.stampSymbol ?? .check }
        if selected == .sticky { stickyStyle = preset.stickyStyle ?? .yellow }
        if selected == .lasso { lassoScope = preset.lassoScope ?? .allContent }
    }
    func matches(_ preset: ToolPreset) -> Bool {
        let preset = preset.sanitized
        guard selected == preset.tool else { return false }
        if selected.usesInkStyle { return ink == preset.ink && (selected != .stamp || stampSymbol == (preset.stampSymbol ?? .check)) }
        if selected == .eraser { return eraserMode == preset.eraserMode && (eraserMode == .strokes || eraserWidth == preset.eraserWidth) }
        if selected == .sticky { return stickyStyle == (preset.stickyStyle ?? .yellow) }
        if selected == .lasso { return lassoScope == (preset.lassoScope ?? .allContent) }
        return true
    }
}
