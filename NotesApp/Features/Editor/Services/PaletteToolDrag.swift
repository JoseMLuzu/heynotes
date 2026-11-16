import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let paletteTool = UTType(exportedAs: "com.local.notesapp.palette-tool", conformingTo: .data)
}

/// A small local value snapshot. No canvas, model, file path or document content is transferred.
struct PaletteToolDrag: Codable, Sendable {
    var version = 1
    let preset: ToolPreset
    var paletteID: UUID? = nil
    var profileID: UUID? = nil

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        guard let data = try? JSONEncoder().encode(self), data.count <= 16_384 else { return provider }
        provider.suggestedName = preset.name
        provider.registerDataRepresentation(forTypeIdentifier: UTType.paletteTool.identifier, visibility: .ownProcess) { completion in
            completion(data, nil); return nil
        }
        return provider
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384 else { throw CocoaError(.coderReadCorrupt) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, (value.paletteID == nil) == (value.profileID == nil) else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
}

@MainActor final class PaletteDropReceiver {
    private let palette: QuickPalettePreferences
    private let profileID: UUID
    private let canInteract: () -> Bool
    private let completed: (Bool, String?) -> Void

    init(palette: QuickPalettePreferences, profileID: UUID, canInteract: @escaping () -> Bool,
         completed: @escaping (Bool, String?) -> Void) {
        self.palette = palette; self.profileID = profileID; self.canInteract = canInteract; self.completed = completed
    }

    /// Start provider loading synchronously inside performDrop; delivery returns to the main actor.
    func receive(_ providers: [NSItemProvider], onto targetID: UUID?) -> Bool {
        guard canInteract(), providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.paletteTool.identifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.paletteTool.identifier) { [self] data, _ in
            let drag = data.flatMap { try? PaletteToolDrag.decode($0) }
            Task { @MainActor in
                guard canInteract(), palette.activeProfile.id == profileID else {
                    completed(false, "The palette changed. Drop the tool again."); return
                }
                guard let drag else { completed(false, "This tool could not be added. Try dragging it again."); return }
                let success = palette.acceptDrop(drag, onto: targetID, in: profileID)
                completed(success, success ? nil : (targetID == nil && palette.favorites.count >= QuickPalettePreferences.maximumFavorites
                    ? "This profile has six favorites. Drop onto a favorite to replace it, or choose another profile."
                    : "The favorite changed. Drop the tool again."))
            }
        }
        return true
    }
}
