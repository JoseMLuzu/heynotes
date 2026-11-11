import SwiftUI

struct QuickInkColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    var sanitized: Self {
        Self(red: ToolPreset.clamp(red, to: 0...1), green: ToolPreset.clamp(green, to: 0...1),
             blue: ToolPreset.clamp(blue, to: 0...1))
    }
    static func defaults(for tool: EditorTool) -> [Self] {
        if tool == .marker {
            return [Self(red: 1, green: 0.78, blue: 0.15), Self(red: 0.95, green: 0.45, blue: 0.60),
                    Self(red: 0.4, green: 0.72, blue: 0.5)]
        }
        return [tool == .pencil ? Self(red: 0.35, green: 0.35, blue: 0.35) : Self(red: 0.08, green: 0.09, blue: 0.09),
                Self(red: 0.15, green: 0.35, blue: 0.8), Self(red: 0.82, green: 0.18, blue: 0.22)]
    }
}

extension ToolPreferences {
    var quickWidths: [Double] {
        let values: [Double] = selected == .marker ? [8, 18, 30] : selected == .pencil ? [1, 2, 4] : [1, 3, 5]
        return values.map { ToolPreset.clamp($0, to: widthRange) }
    }
    var quickEraserSizes: [Double] { [10, 30, 60].map { ToolPreset.clamp($0, to: eraserRange) } }
}
