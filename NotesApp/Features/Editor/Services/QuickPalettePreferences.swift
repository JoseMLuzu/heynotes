import SwiftUI
import Observation

struct PalettePosition: Codable, Equatable {
    var x: Double = 0.04
    var y: Double = 0.2
}

/// Viewport-relative top-left coordinates keep the palette on screen after rotation.
enum PalettePlacement {
    static func origin(_ position: PalettePosition, palette: CGSize, viewport: CGSize) -> CGPoint {
        let bounds = travel(palette: palette, viewport: viewport)
        return CGPoint(x: bounds.minX + bounds.width * ToolPreset.clamp(position.x, to: 0...1),
                       y: bounds.minY + bounds.height * ToolPreset.clamp(position.y, to: 0...1))
    }
    static func clamped(_ origin: CGPoint, palette: CGSize, viewport: CGSize) -> CGPoint {
        let bounds = travel(palette: palette, viewport: viewport)
        return CGPoint(x: min(bounds.maxX, max(bounds.minX, origin.x)), y: min(bounds.maxY, max(bounds.minY, origin.y)))
    }
    static func position(for origin: CGPoint, palette: CGSize, viewport: CGSize, snap: Bool = true) -> PalettePosition {
        let bounds = travel(palette: palette, viewport: viewport)
        var point = clamped(origin, palette: palette, viewport: viewport)
        if snap {
            // In short windows both edges can be within 20 points; use the nearest.
            let edgeX = point.x - bounds.minX <= bounds.maxX - point.x ? bounds.minX : bounds.maxX
            let edgeY = point.y - bounds.minY <= bounds.maxY - point.y ? bounds.minY : bounds.maxY
            if abs(point.x - edgeX) < 20 { point.x = edgeX }
            if abs(point.y - edgeY) < 20 { point.y = edgeY }
        }
        return PalettePosition(x: bounds.width > 0 ? (point.x - bounds.minX) / bounds.width : 0,
                               y: bounds.height > 0 ? (point.y - bounds.minY) / bounds.height : 0)
    }
    private static func travel(palette: CGSize, viewport: CGSize) -> CGRect {
        let insetX = min(12, max(0, (viewport.width - palette.width) / 2))
        let insetY = min(12, max(0, (viewport.height - palette.height) / 2))
        return CGRect(x: insetX, y: insetY, width: max(0, viewport.width - palette.width - insetX * 2),
                      height: max(0, viewport.height - palette.height - insetY * 2))
    }
}

struct PaletteProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var favorites: [ToolPreset]
}

/// A draft stays linked to its original profile even if the selected profile changes.
struct PaletteFavoriteDraft: Identifiable {
    var preset: ToolPreset
    let profileID: UUID
    var id: UUID { preset.id }
}

@MainActor @Observable final class QuickPalettePreferences {
    private struct LegacySaved: Codable {
        var favorites: [ToolPreset]
        var position: PalettePosition
        var collapsed: Bool
        var visible: Bool
    }
    private struct Saved: Codable {
        var profiles: [PaletteProfile]
        var activeProfileID: UUID
        var position = PalettePosition()
        var collapsed = false
        var visible = true
    }
    @ObservationIgnored private let defaults: UserDefaults
    private var saved: Saved
    private static let key = "editor.quickPalette.v2"
    static let maximumFavorites = 6

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        if let data, var value = try? JSONDecoder().decode(Saved.self, from: data) {
            var ids = Set<UUID>()
            value.profiles = value.profiles.filter { ids.insert($0.id).inserted }.map { profile in
                var profile = profile
                profile.name = Self.cleanName(profile.name)
                if profile.name.isEmpty { profile.name = "My Palette" }
                profile.favorites = Self.validFavorites(profile.favorites)
                return profile
            }
            if value.profiles.isEmpty { value.profiles = [PaletteProfile(name: "My Palette", favorites: ToolPreset.initialFavorites)] }
            if !value.profiles.contains(where: { $0.id == value.activeProfileID }) { value.activeProfileID = value.profiles[0].id }
            value.position.x = ToolPreset.clamp(value.position.x, to: 0...1)
            value.position.y = ToolPreset.clamp(value.position.y, to: 0...1)
            saved = value
        } else {
            if let data { defaults.set(data, forKey: Self.key + ".recovery") }
            // Preserve the original v1 blob. Migration only writes the new v2 key.
            if let legacy = defaults.data(forKey: "editor.quickPalette.v1"),
               let value = try? JSONDecoder().decode(LegacySaved.self, from: legacy) {
                let profile = PaletteProfile(name: "My Palette", favorites: Self.validFavorites(value.favorites))
                saved = Saved(profiles: [profile], activeProfileID: profile.id,
                              position: PalettePosition(x: ToolPreset.clamp(value.position.x, to: 0...1), y: ToolPreset.clamp(value.position.y, to: 0...1)),
                              collapsed: value.collapsed, visible: value.visible)
            } else {
                let profile = PaletteProfile(name: "My Palette", favorites: ToolPreset.initialFavorites)
                saved = Saved(profiles: [profile], activeProfileID: profile.id)
            }
        }
        persist()
    }
    var profiles: [PaletteProfile] { saved.profiles }
    private var activeIndex: Int { saved.profiles.firstIndex { $0.id == saved.activeProfileID } ?? 0 }
    var activeProfile: PaletteProfile { saved.profiles[activeIndex] }
    var favorites: [ToolPreset] { activeProfile.favorites }
    var position: PalettePosition { saved.position }
    var isCollapsed: Bool {
        get { saved.collapsed }
        set { saved.collapsed = newValue; persist() }
    }
    var isVisible: Bool {
        get { saved.visible }
        set { saved.visible = newValue; persist() }
    }
    func show() { saved.visible = true; saved.collapsed = false; persist() }
    func togglePresentation() {
        if saved.visible && !saved.collapsed { saved.visible = false; persist() }
        else { show() }
    }
    func place(_ position: PalettePosition) {
        saved.position = PalettePosition(x: ToolPreset.clamp(position.x, to: 0...1), y: ToolPreset.clamp(position.y, to: 0...1))
        persist()
    }
    @discardableResult func selectProfile(_ id: UUID) -> Bool {
        guard saved.profiles.contains(where: { $0.id == id }) else { return false }
        saved.activeProfileID = id; persist(); return true
    }
    func canUseName(_ name: String, excluding id: UUID? = nil) -> Bool {
        let name = Self.cleanName(name)
        return !name.isEmpty && !saved.profiles.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    @discardableResult func createProfile(name: String, initialTool: ToolPreset) -> Bool {
        guard canUseName(name) else { return false }
        let profile = PaletteProfile(name: Self.cleanName(name), favorites: [initialTool.sanitized])
        saved.profiles.append(profile); saved.activeProfileID = profile.id; persist(); return true
    }
    @discardableResult func duplicateProfile(_ id: UUID, name: String) -> Bool {
        guard canUseName(name), let source = saved.profiles.first(where: { $0.id == id }) else { return false }
        let copies = source.favorites.map { favorite in var copy = favorite; copy.id = UUID(); return copy }
        let profile = PaletteProfile(name: Self.cleanName(name), favorites: copies)
        saved.profiles.append(profile); saved.activeProfileID = profile.id; persist(); return true
    }
    @discardableResult func renameProfile(_ id: UUID, name: String) -> Bool {
        guard canUseName(name, excluding: id), let index = saved.profiles.firstIndex(where: { $0.id == id }) else { return false }
        saved.profiles[index].name = Self.cleanName(name); persist(); return true
    }
    @discardableResult func deleteProfile(_ id: UUID) -> Bool {
        guard saved.profiles.count > 1, let index = saved.profiles.firstIndex(where: { $0.id == id }) else { return false }
        saved.profiles.remove(at: index)
        if saved.activeProfileID == id { saved.activeProfileID = saved.profiles[min(index, saved.profiles.count - 1)].id }
        persist(); return true
    }
    @discardableResult func save(_ favorite: ToolPreset, in profileID: UUID? = nil) -> Bool {
        guard let profileIndex = saved.profiles.firstIndex(where: { $0.id == (profileID ?? saved.activeProfileID) }) else { return false }
        var favorites = saved.profiles[profileIndex].favorites
        if let index = favorites.firstIndex(where: { $0.id == favorite.id }) { favorites[index] = favorite.sanitized }
        else {
            guard favorites.count < Self.maximumFavorites else { return false }
            favorites.append(favorite.sanitized)
        }
        saved.profiles[profileIndex].favorites = favorites; persist(); return true
    }
    func remove(_ id: UUID) {
        let index = activeIndex
        guard saved.profiles[index].favorites.count > 1 else { return }
        saved.profiles[index].favorites.removeAll { $0.id == id }; persist()
    }
    func move(from source: IndexSet, to destination: Int) {
        saved.profiles[activeIndex].favorites.move(fromOffsets: source, toOffset: destination); persist()
    }
    private static func cleanName(_ value: String) -> String { String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }
    private static func validFavorites(_ values: [ToolPreset]) -> [ToolPreset] {
        var ids = Set<UUID>()
        let favorites = Array(values.filter { ids.insert($0.id).inserted }.prefix(maximumFavorites)).map(\.sanitized)
        return favorites.isEmpty ? ToolPreset.initialFavorites : favorites
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }
}
