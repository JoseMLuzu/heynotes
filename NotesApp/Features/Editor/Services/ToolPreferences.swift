import SwiftUI
import PencilKit
import Observation

enum EditorTool: String, Codable, CaseIterable {
    case pen, pencil, marker, eraser, lasso
    case line, rectangle, ellipse, arrow, tape, objects
    var title: String {
        switch self { case .marker: "Highlighter"; case .tape: "Study Tape"; case .objects: "Select Objects"; default: rawValue.capitalized }
    }
    var elementKind: PageElementKind? {
        switch self { case .line: .line; case .rectangle: .rectangle; case .ellipse: .ellipse; case .arrow: .arrow; case .tape: .tape; default: nil }
    }
    var usesInkStyle: Bool { inkType != nil || (elementKind != nil && self != .tape) }
    var editsObjects: Bool { elementKind != nil || self == .objects }
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .tape: "rectangle.fill"
        case .objects: "cursorarrow"
        }
    }
    var inkType: PKInkingTool.InkType? {
        switch self { case .pen: .pen; case .pencil: .pencil; case .marker: .marker; default: nil }
    }
}

enum EraserMode: String, Codable, CaseIterable {
    case strokes, precise
    var title: String { self == .strokes ? "Whole Strokes" : "Precise" }
}

struct InkStyle: Codable, Equatable {
    var red: Double = 0.08
    var green: Double = 0.09
    var blue: Double = 0.09
    var width: Double = 3
    var opacity: Double = 1
    var color: Color { Color(red: red, green: green, blue: blue) }
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: opacity) }
}

/// Small local preferences, independent of SwiftData documents and editable PKDrawing files.
@MainActor @Observable
final class ToolPreferences {
    private struct Saved: Codable {
        var selected: EditorTool = .pen
        var pen = InkStyle()
        var pencil = InkStyle(width: 2)
        var marker = InkStyle(red: 1, green: 0.78, blue: 0.15, width: 18, opacity: 0.55)
        var eraserMode: EraserMode = .strokes
        var eraserWidth: Double = 20
        var rulerEnabled: Bool? = nil
        var quickPenColors: [QuickInkColor]? = nil
        var quickPencilColors: [QuickInkColor]? = nil
        var quickMarkerColors: [QuickInkColor]? = nil
    }
    @ObservationIgnored private var saved: Saved
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var previousTool: EditorTool = .eraser
    @ObservationIgnored private var lastNonEraser: EditorTool = .pen
    @ObservationIgnored private var lastInkTool: EditorTool = .pen
    private static let key = "editor.tools.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = value
        } else { saved = Saved() }
        previousTool = saved.selected == .eraser ? .pen : .eraser
        if saved.selected != .eraser { lastNonEraser = saved.selected }
        if saved.selected.usesInkStyle { lastInkTool = saved.selected }
    }

    var selected: EditorTool {
        get { access(keyPath: \.selected); return saved.selected }
        set {
            guard selected != newValue else { return }
            previousTool = saved.selected
            if newValue != .eraser { lastNonEraser = newValue }
            if newValue.usesInkStyle { lastInkTool = newValue }
            withMutation(keyPath: \.selected) { saved.selected = newValue; persist() }
        }
    }
    func toggleEraser() { selected = selected == .eraser ? lastNonEraser : .eraser }
    func selectPreviousTool() { selected = previousTool }
    func selectInkToolForColors() { if !selected.usesInkStyle { selected = lastInkTool } }
    var rulerEnabled: Bool {
        get { access(keyPath: \.rulerEnabled); return saved.rulerEnabled ?? false }
        set {
            guard rulerEnabled != newValue else { return }
            withMutation(keyPath: \.rulerEnabled) { saved.rulerEnabled = newValue; persist() }
        }
    }
    var quickColors: [QuickInkColor] {
        access(keyPath: \.quickColors)
        let colors: [QuickInkColor]?
        switch selected {
        case .pencil: colors = saved.quickPencilColors
        case .marker: colors = saved.quickMarkerColors
        default: colors = saved.quickPenColors
        }
        let fallback = QuickInkColor.defaults(for: selected)
        return (0..<3).map { index in
            if let colors, colors.indices.contains(index) { return colors[index].sanitized }
            return fallback[index]
        }
    }
    @discardableResult func setQuickColor(_ color: Color, at index: Int) -> Bool {
        guard selected.usesInkStyle, (0..<3).contains(index) else { return false }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        var colors = quickColors
        colors[index] = QuickInkColor(red: red, green: green, blue: blue).sanitized
        guard colors != quickColors else { return true }
        withMutation(keyPath: \.quickColors) {
            switch selected {
            case .pencil: saved.quickPencilColors = colors
            case .marker: saved.quickMarkerColors = colors
            default: saved.quickPenColors = colors
            }
            persist()
        }
        return true
    }

    var eraserMode: EraserMode {
        get { access(keyPath: \.eraserMode); return saved.eraserMode }
        set {
            guard eraserMode != newValue else { return }
            withMutation(keyPath: \.eraserMode) { saved.eraserMode = newValue; persist() }
        }
    }
    var eraserRange: ClosedRange<Double> {
        ToolPreset.eraserRange
    }
    var eraserWidth: Double {
        get { access(keyPath: \.eraserWidth); return clamp(saved.eraserWidth, to: eraserRange) }
        set {
            let value = clamp(newValue, to: eraserRange)
            guard eraserWidth != value else { return }
            withMutation(keyPath: \.eraserWidth) { saved.eraserWidth = value; persist() }
        }
    }
    var widthRange: ClosedRange<Double> {
        ToolPreset.widthRange(for: selected)
    }
    var ink: InkStyle {
        get {
            access(keyPath: \.ink)
            var value: InkStyle
            switch selected { case .pencil: value = saved.pencil; case .marker: value = saved.marker; default: value = saved.pen }
            value.width = clamp(value.width, to: widthRange)
            value.opacity = clamp(value.opacity, to: 0.1...1)
            value.red = clamp(value.red, to: 0...1); value.green = clamp(value.green, to: 0...1); value.blue = clamp(value.blue, to: 0...1)
            return value
        }
        set {
            guard selected.usesInkStyle else { return }
            var value = newValue
            value.width = clamp(value.width, to: widthRange)
            value.opacity = clamp(value.opacity, to: 0.1...1)
            value.red = clamp(value.red, to: 0...1); value.green = clamp(value.green, to: 0...1); value.blue = clamp(value.blue, to: 0...1)
            guard ink != value else { return }
            withMutation(keyPath: \.ink) {
                switch selected { case .pencil: saved.pencil = value; case .marker: saved.marker = value; default: saved.pen = value }
                persist()
            }
        }
    }
    var tool: PKTool {
        if let type = selected.inkType { return PKInkingTool(type, color: ink.uiColor, width: ink.width) }
        if selected == .eraser {
            return eraserMode == .strokes ? PKEraserTool(.vector) : PKEraserTool(.fixedWidthBitmap, width: eraserWidth)
        }
        return PKLassoTool()
    }
    func setColor(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        var value = ink
        value.red = red; value.green = green; value.blue = blue
        ink = value
    }
    func matchesColor(_ color: Color) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return abs(ink.red - Double(red)) < 0.005 && abs(ink.green - Double(green)) < 0.005 && abs(ink.blue - Double(blue)) < 0.005
    }
    func resetCurrentTool() {
        let initial = Saved()
        switch selected {
        case .pen, .line, .rectangle, .ellipse, .arrow: ink = initial.pen
        case .pencil: ink = initial.pencil
        case .marker: ink = initial.marker
        case .eraser: eraserMode = initial.eraserMode; eraserWidth = initial.eraserWidth
        default: break
        }
    }
    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }
}
