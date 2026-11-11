import SwiftUI

struct PaletteManager: View {
    let palette: QuickPalettePreferences
    let tools: ToolPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PaletteFavoriteDraft?
    @State private var showingProfiles = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Profile", selection: Binding(get: { palette.activeProfile.id }, set: { palette.selectProfile($0) })) {
                        ForEach(palette.profiles) { Text($0.name).tag($0.id) }
                    }
                    Button("Manage Profiles", systemImage: "rectangle.stack") { showingProfiles = true }
                }
                Section {
                    ForEach(palette.favorites) { favorite in
                        Button { edit(favorite) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: favorite.tool.symbol)
                                    .foregroundStyle(favorite.tool.usesInkStyle ? favorite.ink.color : AppTheme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(favorite.name).foregroundStyle(.primary)
                                    Text("\(favorite.tool.title) · \(favorite.detail)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                        .deleteDisabled(palette.favorites.count <= 1)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { palette.favorites[$0].id }
                        for id in ids { palette.remove(id) }
                    }
                    .onMove { palette.move(from: $0, to: $1) }
                } header: { Text("Favorites") } footer: {
                    Text("Save up to six tools. Tap a favorite to edit it, swipe to remove it, or use Edit to reorder. At least one favorite is kept.")
                }
                Section {
                    Button("Add Current Tool", systemImage: "plus") { edit(tools.capturePreset()) }
                        .disabled(palette.favorites.count >= QuickPalettePreferences.maximumFavorites)
                }
            }
            .navigationTitle("Quick Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { draft in ToolPresetEditor(draft: draft.preset) { palette.save($0, in: draft.profileID) } }
            .sheet(isPresented: $showingProfiles) { PaletteProfileManager(palette: palette, tools: tools) }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
    }
    private func edit(_ preset: ToolPreset) { editing = PaletteFavoriteDraft(preset: preset, profileID: palette.activeProfile.id) }
}
