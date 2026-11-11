import Foundation

public struct ThemeColorValue: Codable, Equatable, Sendable {
    public let red, green, blue: Double
    public init(red: Double, green: Double, blue: Double) {
        func clean(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        self.red = clean(red); self.green = clean(green); self.blue = clean(blue)
    }
    public var sanitized: Self { Self(red: red, green: green, blue: blue) }
    public var luminance: Double {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func mixed(with other: Self, amount: Double) -> Self {
        let t = min(1, max(0, amount))
        return Self(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                    blue: blue + (other.blue - blue) * t)
    }
}

public enum FolderColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case sage, blue, teal, lavender, rose, coral, amber, graphite
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var value: ThemeColorValue {
        switch self {
        case .sage: .init(red: 0.40, green: 0.53, blue: 0.44)
        case .blue: .init(red: 0.35, green: 0.53, blue: 0.75)
        case .teal: .init(red: 0.22, green: 0.58, blue: 0.57)
        case .lavender: .init(red: 0.57, green: 0.45, blue: 0.74)
        case .rose: .init(red: 0.72, green: 0.43, blue: 0.54)
        case .coral: .init(red: 0.78, green: 0.45, blue: 0.35)
        case .amber: .init(red: 0.76, green: 0.57, blue: 0.25)
        case .graphite: .init(red: 0.40, green: 0.43, blue: 0.47)
        }
    }
}
