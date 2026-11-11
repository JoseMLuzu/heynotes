import SwiftUI

/// Only this grip can move the palette. Pencil input never starts the pan recognizer.
struct PaletteDragHandle: UIViewRepresentable {
    let canMove: () -> Bool
    let changed: (CGSize) -> Void
    let ended: (CGSize, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let icon = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        icon.tintColor = .secondaryLabel; icon.contentMode = .center
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
        view.accessibilityHint = "Drag with one finger. Palette Options also offers corner positions."
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
