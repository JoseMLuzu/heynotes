import SwiftUI

extension CoverColor {
    var color: Color {
        switch self {
        case .sage: Color(red: 0.40, green: 0.53, blue: 0.44)
        case .blue: Color(red: 0.38, green: 0.49, blue: 0.61)
        case .sand: Color(red: 0.67, green: 0.55, blue: 0.40)
        case .rose: Color(red: 0.65, green: 0.43, blue: 0.46)
        case .graphite: Color(red: 0.37, green: 0.41, blue: 0.43)
        }
    }
}

enum AppTheme {
    @MainActor static var accent: Color { AppPreferences.shared.accentColor }
    @MainActor static var headerBackground: Color { AppPreferences.shared.headerBackground }
    static let lightBackground = ThemeColorValue(red: 0.97, green: 0.965, blue: 0.95)
    static let darkBackground = ThemeColorValue(red: 0.09, green: 0.10, blue: 0.095)
    static let background = Color(uiColor: UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? darkBackground : lightBackground)
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let controlSurface = Color.primary.opacity(0.045)
    static let canvasUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.065, green: 0.075, blue: 0.07, alpha: 1)
            : UIColor(red: 0.925, green: 0.93, blue: 0.91, alpha: 1)
    }
}

/// A small tactile response for library controls; never applied to the handwriting canvas.
struct QuietPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(configuration.isPressed || reduceMotion ? nil : .easeOut(duration: 0.09), value: configuration.isPressed)
    }
}
