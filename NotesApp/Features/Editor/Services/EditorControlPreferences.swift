import SwiftUI
import UIKit

/// StateObject lazily creates this owner once per editor identity. The contained
/// Observation models still track tool/palette changes individually in their consumers.
@MainActor final class EditorControlPreferences: ObservableObject {
    enum PencilAction: Equatable { case toolChanged, toolOptions, contextualPalette }
    let tools: ToolPreferences
    let palette: QuickPalettePreferences

    init(defaults: UserDefaults, palette: QuickPalettePreferences?) {
        tools = ToolPreferences(defaults: defaults)
        self.palette = palette ?? QuickPalettePreferences(defaults: defaults)
    }

    func performPencilAction(_ action: UIPencilPreferredAction) -> PencilAction? {
        if #available(iOS 17.5, *) {
            if action == .showContextualPalette { return .contextualPalette }
            if action == .runSystemShortcut { return nil } // The system owns shortcut execution.
        }
        switch action {
        case .switchEraser: tools.toggleEraser(); return .toolChanged
        case .switchPrevious: tools.selectPreviousTool(); return .toolChanged
        case .showColorPalette: tools.selectInkToolForColors(); return .toolOptions
        case .showInkAttributes: return .toolOptions
        default: return nil
        }
    }
}
