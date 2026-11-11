import SwiftUI
import Observation

@MainActor @Observable final class AppPreferences {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    }
    static let shared = AppPreferences()
    static let defaultAccent = FolderColor.blue.value
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var palette: AccentPalette
    var accent: ThemeColorValue {
        didSet {
            guard oldValue != accent else { return }
            palette = AccentPalette(accent)
            if let data = try? JSONEncoder().encode(accent) { defaults.set(data, forKey: "app.accent.v1") }
        }
    }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "app.appearance.v1") } }
    var defaultPaper: PaperTemplate { didSet { defaults.set(defaultPaper.rawValue, forKey: "app.defaultPaper.v1") } }
    var accentColor: Color { _ = accent; return palette.color }
    var accentUIColor: UIColor { _ = accent; return palette.uiColor }
    var headerBackground: Color { _ = accent; return palette.headerBackground }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedAccent = defaults.data(forKey: "app.accent.v1")
            .flatMap { try? JSONDecoder().decode(ThemeColorValue.self, from: $0) }?.sanitized
        // Upgrade the former default once. Sage remains selectable after this upgrade.
        let upgradesLegacySage = defaults.integer(forKey: "app.accent.defaultsVersion") < 2
            && savedAccent == FolderColor.sage.value
        let value = upgradesLegacySage ? Self.defaultAccent : (savedAccent ?? Self.defaultAccent)
        if upgradesLegacySage, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "app.accent.v1")
        }
        defaults.set(2, forKey: "app.accent.defaultsVersion")
        accent = value; palette = AccentPalette(value)
        appearance = defaults.string(forKey: "app.appearance.v1").flatMap(Appearance.init(rawValue:)) ?? .system
        let paper = defaults.string(forKey: "app.defaultPaper.v1").flatMap(PaperTemplate.init(rawValue:)) ?? .blank
        defaultPaper = Self.basicPapers.contains(paper) ? paper : .blank
    }
    static let basicPapers: [PaperTemplate] = [.blank, .ruled, .grid, .dotted, .cornell]
    func resetAppearance() { accent = Self.defaultAccent; appearance = .system }
}
