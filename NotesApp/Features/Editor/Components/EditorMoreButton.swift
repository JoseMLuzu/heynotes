import SwiftUI
import UIKit

/// A native 44-point control: the empty space around the symbol is also tappable.
/// It uses UIControl activation instead of adding another SwiftUI gesture recognizer.
struct EditorMoreButton: UIViewRepresentable {
    let title: String
    var identifier: String = ""
    var symbol: String = "ellipsis"
    var menu: UIMenu? = nil
    var action: () -> Void = {}
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(textStyle: .body), forImageIn: .normal)
        button.tintColor = .label
        button.addTarget(context.coordinator, action: #selector(Coordinator.activate(_:)), for: .primaryActionTriggered)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.isEnabled = isEnabled
        button.menu = menu
        button.showsMenuAsPrimaryAction = menu != nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }
    static func dismantleUIView(_ button: UIButton, coordinator: Coordinator) {
        button.removeTarget(coordinator, action: nil, for: .allEvents)
        button.menu = nil
        coordinator.action = {}
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate(_ sender: UIButton) {
            guard sender.isEnabled else { return }
            action()
        }
    }
}
