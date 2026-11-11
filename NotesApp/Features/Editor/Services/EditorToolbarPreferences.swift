import SwiftUI
import Observation

enum EditorToolbarPosition: String, CaseIterable, Identifiable {
    case top, bottom, left, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var isVertical: Bool { self == .left || self == .right }
    var symbol: String {
        switch self {
        case .top: "rectangle.topthird.inset.filled"
        case .bottom: "rectangle.bottomthird.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        }
    }
    var popoverEdge: Edge {
        switch self { case .top: .top; case .bottom: .bottom; case .left: .leading; case .right: .trailing }
    }
}

/// Device-local layout preference; moving tools never changes a notebook or its ink.
@MainActor @Observable final class EditorToolbarPreferences {
    static let shared = EditorToolbarPreferences()
    static let key = "editor.toolbar.position.v1"
    @ObservationIgnored private let defaults: UserDefaults
    var position: EditorToolbarPosition {
        didSet { defaults.set(position.rawValue, forKey: Self.key) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        position = defaults.string(forKey: Self.key).flatMap(EditorToolbarPosition.init(rawValue:)) ?? .top
    }
}
