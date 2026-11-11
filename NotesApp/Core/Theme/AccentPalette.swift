import UIKit
import SwiftUI

/// Preserve the chosen hue while limiting saturation and adapting foreground contrast.
struct AccentPalette {
    let light, dark, highLight, highDark: ThemeColorValue
    let uiColor: UIColor
    let headerBackground: Color
    var color: Color { Color(uiColor: uiColor) }

    init(_ raw: ThemeColorValue) {
        let source = raw.sanitized
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        UIColor(source).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let base = ThemeColorValue(UIColor(hue: hue, saturation: min(0.75, saturation), brightness: brightness, alpha: 1)) ?? source
        let black = ThemeColorValue(red: 0, green: 0, blue: 0), white = ThemeColorValue(red: 1, green: 1, blue: 1)
        func foreground(_ target: Double, toward end: ThemeColorValue, darker: Bool) -> ThemeColorValue {
            if darker ? base.luminance <= target : base.luminance >= target { return base }
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let mid = (low + high) / 2, value = base.mixed(with: end, amount: mid)
                if darker ? value.luminance > target : value.luminance < target { low = mid } else { high = mid }
            }
            return base.mixed(with: end, amount: high)
        }
        let light = foreground(0.10, toward: black, darker: true)
        let dark = foreground(0.52, toward: white, darker: false)
        let highLight = foreground(0.075, toward: black, darker: true)
        let highDark = foreground(0.68, toward: white, darker: false)
        self.light = light; self.dark = dark; self.highLight = highLight; self.highDark = highDark
        let foregroundColor = UIColor { traits in
            let high = traits.accessibilityContrast == .high
            return UIColor(traits.userInterfaceStyle == .dark ? (high ? highDark : dark) : (high ? highLight : light))
        }
        uiColor = foregroundColor
        headerBackground = Color(uiColor: UIColor { traits in
            let base = traits.userInterfaceStyle == .dark ? AppTheme.darkBackground : AppTheme.lightBackground
            let resolvedAccent = foregroundColor.resolvedColor(with: traits)
            let accent = ThemeColorValue(resolvedAccent) ?? base
            return UIColor(base.mixed(with: accent, amount: 0.12))
        })
    }
}

extension UIColor {
    convenience init(_ value: ThemeColorValue) { self.init(red: value.red, green: value.green, blue: value.blue, alpha: 1) }
}
extension ThemeColorValue {
    init?(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: nil) else { return nil }
        self.init(red: r, green: g, blue: b)
    }
}
extension FolderColor {
    var color: Color { FolderColorTokens.colors[self] ?? .secondary }
}
private enum FolderColorTokens {
    static let colors: [FolderColor: Color] = Dictionary(uniqueKeysWithValues: FolderColor.allCases.map { ($0, AccentPalette($0.value).color) })
}
