import SwiftUI

/// A crisp color marker with quiet concentric halos, drawn without blur or animation.
struct AuraDot: View {
    let color: Color
    var diameter: CGFloat = 8
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(color.opacity(contrast == .increased ? 0.34 : 0.22))
                    .padding(-3)
            }
            .background {
                Circle().fill(color.opacity(contrast == .increased ? 0.14 : 0.08))
                    .padding(-5)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
