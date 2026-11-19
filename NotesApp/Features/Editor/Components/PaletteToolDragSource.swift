import SwiftUI

/// System drag recognition leaves the existing short-tap action and button style in place.
struct PaletteToolDragSource: ViewModifier {
    let snapshot: () -> ToolPreset
    let palette: QuickPalettePreferences
    var fromFavorite = false
    let canInteract: () -> Bool
    var didPrepareDrag: (() -> Void)? = nil

    func provider() -> NSItemProvider {
        guard canInteract() else { return NSItemProvider() }
        let drag = PaletteToolDrag(preset: snapshot(), paletteID: fromFavorite ? palette.dragScopeID : nil,
                                   profileID: fromFavorite ? palette.activeProfile.id : nil)
        if !fromFavorite { palette.show() }
        didPrepareDrag?()
        return drag.itemProvider()
    }

    func body(content: Content) -> some View {
        content
            .contentShape(.dragPreview, Circle())
            .onDrag { provider() } preview: {
                let preset = snapshot()
                Image(systemName: preset.tool.symbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(preset.tool.usesInkStyle ? preset.ink.color : AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(.dragPreview, Circle())
            }
    }
}
