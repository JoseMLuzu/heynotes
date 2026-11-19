import UIKit

/// Public installed faces. Imported faces are added by the font store, without downloading fonts.
enum HandwritingFont {
    struct Choice: Identifiable {
        let name: String
        let title: String
        var id: String { name }
    }
    static var choices: [Choice] {
        [Choice(name: "Noteworthy-Light", title: "Noteworthy"),
         Choice(name: "ChalkboardSE-Regular", title: "Chalkboard"),
         Choice(name: "MarkerFelt-Thin", title: "Marker Felt"),
         Choice(name: "SnellRoundhand", title: "Roundhand"),
         Choice(name: "BradleyHandITCTT-Bold", title: "Bradley Hand"),
         Choice(name: "Chalkduster", title: "Chalkduster"),
         Choice(name: "AmericanTypewriter", title: "Typewriter"),
         Choice(name: "Cochin", title: "Cochin"),
         Choice(name: "Palatino-Roman", title: "Palatino"),
         Choice(name: "Georgia", title: "Georgia"),
         Choice(name: "AvenirNext-Regular", title: "Avenir")]
            .filter { UIFont(name: $0.name, size: 24) != nil }
    }
    static func choices(including imported: [HandwritingFontAsset], current: String? = nil) -> [Choice] {
        var result = choices, names = Set(result.map(\.name))
        for asset in imported where names.insert(asset.name).inserted { result.append(asset.choice) }
        if let current, !current.isEmpty, names.insert(current).inserted {
            result.append(Choice(name: current, title: UIFont(name: current, size: 24)?.familyName ?? current))
        }
        return result
    }
    static var defaultName: String { choices.first?.name ?? "" }
    static func resolve(_ name: String?, size: CGFloat) -> UIFont {
        if let name, let font = UIFont(name: name, size: size) { return font }
        return .systemFont(ofSize: size)
    }
}
