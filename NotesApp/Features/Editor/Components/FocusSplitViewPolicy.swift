import SwiftUI
import UIKit

/// Hide the sidebar through SwiftUI; prevent its native edge gesture while focused.
/// Restore the controller's original gesture policy on exit or removal.
struct FocusSplitViewPolicy: UIViewRepresentable {
    let focused: Bool
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.focusEnabled = focused; view.apply()
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.restore() }

    final class Probe: UIView {
        var focusEnabled = false
        private weak var split: UISplitViewController?
        private var previousGesture: Bool?
        override init(frame: CGRect) {
            super.init(frame: frame); isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { restore() } else { apply() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if focusEnabled && split == nil { apply() }
        }
        func apply() {
            guard focusEnabled else { restore(); return }
            guard split == nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController {
                    var parent: UIViewController? = controller
                    while let candidate = parent {
                        if let found = candidate as? UISplitViewController {
                            split = found; previousGesture = found.presentsWithGesture
                            found.presentsWithGesture = false
                            return
                        }
                        parent = candidate.parent
                    }
                }
                responder = current.next
            }
        }
        func restore() {
            if let previousGesture { split?.presentsWithGesture = previousGesture }
            previousGesture = nil; split = nil
        }
    }
}
