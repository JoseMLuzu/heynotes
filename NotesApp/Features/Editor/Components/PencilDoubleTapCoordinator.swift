import UIKit

/// One interaction on the active canvas container, including when an object tool is selected.
@MainActor final class PencilDoubleTapCoordinator: NSObject, UIPencilInteractionDelegate {
    var onTap: ((UIPencilPreferredAction) -> Void)?
    private(set) lazy var interaction: UIPencilInteraction = {
        if #available(iOS 17.5, *) { return UIPencilInteraction(delegate: self) }
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        return interaction
    }()

    func receiveTap(_ action: UIPencilPreferredAction) {
        guard interaction.isEnabled, let view = interaction.view,
              let window = view.window, !window.isHidden, !view.isHidden else { return }
        onTap?(action)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        receiveTap(UIPencilInteraction.preferredTapAction)
    }

    // Required only by the iPadOS 17.0–17.4 deployment fallback. Modern systems call the method above.
    @available(iOS, introduced: 12.1, deprecated: 17.5)
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        receiveTap(UIPencilInteraction.preferredTapAction)
    }

    func detach() {
        interaction.isEnabled = false
        interaction.view?.removeInteraction(interaction)
        onTap = nil
    }
}
