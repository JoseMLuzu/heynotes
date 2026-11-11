import SwiftUI
import UIKit

/// Immediate touch-down feedback. A short release settles the button without delaying
/// selection or propagating an animation transaction into PencilKit/tool configuration.
struct EditorToolbarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(.primary.opacity(configuration.isPressed ? 0.08 : 0), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(configuration.isPressed || reduceMotion ? nil : .easeOut(duration: 0.09), value: configuration.isPressed)
    }
}
