import SwiftUI

/// Each favorite owns its native drop interaction and carries its permanent destination ID.
/// The + destination appends; no screen/grid coordinates are used to identify a favorite.
struct PaletteToolDrop: DropDelegate {
    let palette: QuickPalettePreferences
    let profileID: UUID
    var favoriteID: UUID? = nil
    let canInteract: () -> Bool
    let hovering: (UUID?, Bool) -> Void
    let completed: (Bool, String?) -> Void

    private var available: Bool {
        canInteract() && palette.activeProfile.id == profileID &&
            (favoriteID == nil || palette.favorites.contains { $0.id == favoriteID })
    }
    func validateDrop(info: DropInfo) -> Bool { available && info.hasItemsConforming(to: [.paletteTool]) }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { hovering(favoriteID, true) } }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { hovering(favoriteID, false); return DropProposal(operation: .forbidden) }
        hovering(favoriteID, true)
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { hovering(favoriteID, false) }
    func performDrop(info: DropInfo) -> Bool {
        hovering(favoriteID, false)
        guard validateDrop(info: info) else { return false }
        return receive(info.itemProviders(for: [.paletteTool]))
    }
    /// The native interaction and tests share exactly the same explicitly identified destination.
    func receive(_ providers: [NSItemProvider]) -> Bool {
        guard available else { return false }
        let receiver = PaletteDropReceiver(palette: palette, profileID: profileID, canInteract: canInteract, completed: completed)
        return receiver.receive(providers, onto: favoriteID)
    }
}
