import SwiftUI

struct AppSettingsView: View {
    @Bindable var preferences: AppPreferences = .shared
    @Bindable var toolbar: EditorToolbarPreferences = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Color.gray

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $preferences.appearance) {
                        ForEach(AppPreferences.Appearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent Color").font(.subheadline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68))], spacing: 8) {
                            ForEach(FolderColor.allCases) { color in
                                ColorChoiceButton(title: color.title, color: color.color,
                                                  selected: preferences.accent == color.value) { preferences.accent = color.value }
                            }
                        }
                    }.padding(.vertical, 8)
                    ColorPicker("Custom Accent", selection: $custom, supportsOpacity: false)
                    Button("Apply Custom Color") {
                        if let value = ThemeColorValue(UIColor(custom)) { preferences.accent = value }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "sidebar.left").foregroundStyle(preferences.accentColor)
                        Text("A little color, a clear space.").font(.subheadline)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(preferences.accentColor)
                    }
                    .padding(12)
                    .background(preferences.headerBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(preferences.accentColor.opacity(0.14)).allowsHitTesting(false))
                    Button("Reset Appearance") { preferences.resetAppearance() }
                } header: { Text("Appearance") } footer: {
                    Text("The accent adapts to Light and Dark Mode and adds color to the header, controls and selections.")
                }
                Section("Editor Defaults") {
                    Picker("Toolbar Position", selection: $toolbar.position) {
                        ForEach(EditorToolbarPosition.allCases) { position in Label(position.title, systemImage: position.symbol).tag(position) }
                    }
                    Picker("New Notebook Paper", selection: $preferences.defaultPaper) {
                        ForEach(AppPreferences.basicPapers, id: \.self) { template in Text(template.title).tag(template) }
                    }
                    Text("Paper changes apply to new notebooks. Existing pages retain their templates.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Storage", value: "On this iPad")
                    Text("Your notes work offline, without an account.").font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Version", value: version)
                    Text("Write. Study. Remember.").font(.system(.footnote, design: .serif)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appSheetPresentation()
        .modifier(AppAppearance(preferences: preferences))
        .onAppear { custom = Color(uiColor: UIColor(preferences.accent)) }
        .onChange(of: preferences.accent) { custom = Color(uiColor: UIColor($1)) }
    }
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct AppAppearance: ViewModifier {
    @Bindable var preferences: AppPreferences = .shared
    func body(content: Content) -> some View {
        content.tint(preferences.accentColor).preferredColorScheme(preferences.appearance.colorScheme)
    }
}
