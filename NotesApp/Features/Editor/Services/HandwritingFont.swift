import UIKit

/// Public system fonts only. A missing font always falls back to the system face.
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
         Choice(name: "SnellRoundhand", title: "Roundhand")]
            .filter { UIFont(name: $0.name, size: 24) != nil }
    }
    static var defaultName: String { choices.first?.name ?? "" }
    static func resolve(_ name: String?, size: CGFloat) -> UIFont {
        if let name, let font = UIFont(name: name, size: size) { return font }
        return .systemFont(ofSize: size)
    }
}
