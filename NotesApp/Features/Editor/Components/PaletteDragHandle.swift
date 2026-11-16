import SwiftUI

/// Only this grip can move the palette, with a finger.
struct PaletteDragHandle: UIViewRepresentable {
    let canMove: () -> Bool
    let changed: (CGSize) -> Void
    let ended: (CGSize, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Six native dots stay crisp and adapt their color without relying on a symbol variant.
        let icon = UIStackView(); icon.axis = .vertical; icon.spacing = 3
        icon.isUserInteractionEnabled = false; icon.accessibilityElementsHidden = true
        for _ in 0..<3 {
            let row = UIStackView(); row.spacing = 3
            for _ in 0..<2 {
                let dot = UIView(); dot.backgroundColor = .tertiaryLabel; dot.layer.cornerRadius = 1.5
                NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 3), dot.heightAnchor.constraint(equalToConstant: 3)])
                row.addArrangedSubview(dot)
            }
            icon.addArrangedSubview(row)
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(icon)
        NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     icon.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Move Quick Palette"
        view.accessibilityHint = "Drag with one finger. The profile menu also offers corner positions."
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PaletteDragHandle
        init(_ parent: PaletteDragHandle) { self.parent = parent }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { parent.canMove() }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view?.window)
            let offset = CGSize(width: translation.x, height: translation.y)
            switch gesture.state {
            case .began, .changed: parent.changed(offset)
            case .ended: parent.ended(offset, false)
            case .cancelled, .failed: parent.ended(.zero, true)
            default: break
            }
        }
    }
}
