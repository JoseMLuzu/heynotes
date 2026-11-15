import SwiftUI

enum PaletteDropLayout {
    static func favoriteIndex(at point: CGPoint, in grid: CGRect, count: Int) -> Int? {
        guard grid.contains(point) else { return nil }
        let x = point.x - grid.minX, y = point.y - grid.minY
        let column = Int(x / 48), row = Int(y / 48)
        guard column < 3, x.truncatingRemainder(dividingBy: 48) < 44,
              y.truncatingRemainder(dividingBy: 48) < 44 else { return nil }
        let index = row * 3 + column
        return index < count ? index : nil
    }
}

struct PaletteGridFrame: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Only the palette rectangle receives drops; hovering never changes saved order/preferences.
struct PaletteToolDrop: DropDelegate {
    let palette: QuickPalettePreferences
    let profileID: UUID
    let grid: CGRect
    let canInteract: () -> Bool
    let hovering: (Bool, UUID?) -> Void
    let completed: (Bool, String?) -> Void

    func validateDrop(info: DropInfo) -> Bool { canInteract() && info.hasItemsConforming(to: [.paletteTool]) }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        update(info)
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { hovering(false, nil) }
    func performDrop(info: DropInfo) -> Bool {
        hovering(false, nil)
        guard validateDrop(info: info) else { return false }
        let receiver = PaletteDropReceiver(palette: palette, profileID: profileID, canInteract: canInteract, completed: completed)
        return receiver.receive(info.itemProviders(for: [.paletteTool]), onto: target(at: info.location))
    }
    private func target(at point: CGPoint) -> UUID? {
        guard let index = PaletteDropLayout.favoriteIndex(at: point, in: grid, count: palette.favorites.count) else { return nil }
        return palette.favorites[index].id
    }
    private func update(_ info: DropInfo) { hovering(true, target(at: info.location)) }
}
