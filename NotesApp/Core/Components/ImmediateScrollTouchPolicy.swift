import SwiftUI
import UIKit

/// Remove touch-down waiting only from the nearest enclosing scroll view.
/// Attach inside scroll content; this never changes global UIScrollView appearance.
struct ImmediateScrollTouchPolicy: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.configureScrollView() }

    final class Probe: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func didMoveToWindow() { super.didMoveToWindow(); configureScrollView() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); configureScrollView() }

        func configureScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    scroll.delaysContentTouches = false
                    scroll.canCancelContentTouches = true
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
