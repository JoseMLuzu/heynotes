import SwiftUI

struct PaletteProfileManager: View {
    let palette: QuickPalettePreferences
    let tools: ToolPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var naming: NameAction?
    @State private var name = ""
    @State private var deleting: PaletteProfile?

    private enum NameAction {
        case create, rename(UUID), duplicate(UUID)
        var title: String {
            switch self { case .create: "New Palette Profile"; case .rename: "Rename Profile"; case .duplicate: "Duplicate Profile" }
        }
        var excludedID: UUID? { if case .rename(let id) = self { return id }; return nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(palette.profiles) { profile in
                        HStack(spacing: 8) {
                            Button { palette.selectProfile(profile.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: profile.id == palette.activeProfile.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(AppTheme.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name).foregroundStyle(.primary)
                                        Text("\(profile.favorites.count) \(profile.favorites.count == 1 ? "favorite" : "favorites")").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(profile.id == palette.activeProfile.id ? .isSelected : [])
                            Menu {
                                Button("Rename", systemImage: "pencil") { begin(.rename(profile.id), name: profile.name) }
                                Button("Duplicate", systemImage: "doc.on.doc") { begin(.duplicate(profile.id), name: String(profile.name.prefix(30)) + " Copy") }
                                Button("Delete Profile", systemImage: "trash", role: .destructive) { deleting = profile }
                                    .disabled(palette.profiles.count <= 1)
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Options for \(profile.name)")
                        }
                    }
                } header: { Text("Profiles") } footer: {
                    Text("Each profile has its own favorites. Switching profiles keeps your current writing tool until you choose a favorite. At least one profile is kept.")
                }
                Section {
                    Button("New Profile", systemImage: "plus") { begin(.create, name: "") }
                    Text("A new profile starts with your current tool. Duplicate a profile to copy all its favorites.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Palette Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(naming?.title ?? "Profile Name", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                if let action = naming {
                    TextField("Name", text: $name)
                    Button("Cancel", role: .cancel) { naming = nil }
                    Button("Save") { commit(action) }
                        .disabled(!palette.canUseName(name, excluding: action.excludedID))
                }
            } message: { Text("Choose a unique name, such as Class, Review or PDF. Names can contain up to 40 characters.") }
            .confirmationDialog("Delete this palette profile?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { profile in
                Button("Delete \(profile.name)", role: .destructive) { palette.deleteProfile(profile.id) }
            } message: { profile in Text("This removes \(profile.name) and its \(profile.favorites.count) saved favorites.") }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
    }
    private func begin(_ action: NameAction, name: String) { self.name = name; naming = action }
    private func commit(_ action: NameAction) {
        switch action {
        case .create: palette.createProfile(name: name, initialTool: tools.capturePreset())
        case .rename(let id): palette.renameProfile(id, name: name)
        case .duplicate(let id): palette.duplicateProfile(id, name: name)
        }
    }
}
