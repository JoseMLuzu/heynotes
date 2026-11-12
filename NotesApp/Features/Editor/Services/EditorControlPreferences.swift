import SwiftUI

/// StateObject lazily creates this owner once per editor identity. The contained
/// Observation models still track tool/palette changes individually in their consumers.
@MainActor final class EditorControlPreferences: ObservableObject {
    let tools: ToolPreferences
    let palette: QuickPalettePreferences

    init(defaults: UserDefaults, palette: QuickPalettePreferences?) {
        tools = ToolPreferences(defaults: defaults)
        self.palette = palette ?? QuickPalettePreferences(defaults: defaults)
    }
}
