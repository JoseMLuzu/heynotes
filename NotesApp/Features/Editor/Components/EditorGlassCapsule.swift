import SwiftUI

/// Glass is confined to controls, leaving the PencilKit surface opaque and responsive.
struct EditorGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(EditorGlassSurface(shape: Capsule()))
    }
}

/// One material policy for the navigation band and the more rounded drawing controls.
struct EditorGlassSurface<Surface: InsettableShape>: ViewModifier {
    let shape: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        // The material is decoration, not a compositing group around all buttons.
        // A menu/context-menu may lift its source; it must not lift the whole toolbar.
        content.background {
            backdrop.allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var backdrop: some View {
        if reduceTransparency {
            shape.fill(AppTheme.surface)
                .overlay(shape.strokeBorder(AppTheme.accent.opacity(0.12)))
        } else if #available(iOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(AppTheme.accent.opacity(0.08)))
        } else {
            shape.fill(.regularMaterial)
                .overlay(shape.strokeBorder(AppTheme.accent.opacity(0.08)))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }
}
