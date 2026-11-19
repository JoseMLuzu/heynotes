import SwiftUI
import UniformTypeIdentifiers

struct HandwritingStyleView: View {
    @Bindable var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var imported: [HandwritingFontAsset] = []
    @State private var showingFontImporter = false
    @State private var importing = false
    @State private var fontError: String?

    var body: some View {
        @Bindable var assistant = session.handwriting
        NavigationStack {
            Form {
                Section {
                    Toggle("Convert After a Pause", isOn: Binding(get: { assistant.enabled }, set: {
                        assistant.setEnabled($0, session: session)
                    }))
                    Text("Write a short phrase with Pen or Pencil, then pause for 1.2 seconds. Only new handwriting is converted. Highlighter, eraser and selection stay unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Handwriting Style · Experimental") }
                Section("Style") {
                    Picker("Font", selection: Binding(get: { assistant.fontName }, set: { name in
                        assistant.fontFilePath = imported.first { $0.name == name }?.path
                        assistant.fontName = name
                    })) {
                        ForEach(HandwritingFont.choices(including: imported, current: assistant.fontName)) { choice in
                            Text(choice.title).font(.custom(choice.name, size: 20)).tag(choice.name)
                        }
                    }
                    Text("Write. Study. Remember.")
                        .font(.custom(assistant.fontName, size: 30))
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .accessibilityLabel("Font preview: Write. Study. Remember.")
                    Button("Import Your Font…", systemImage: "square.and.arrow.down") { showingFontImporter = true }
                        .disabled(importing)
                    if importing { ProgressView("Importing font…") }
                    Text("Import a .ttf or .otf file, including a font made from your handwriting. Fonts stay on this iPad and travel with notes in library backups.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("Recognition Language", selection: $assistant.language) {
                        Text("English").tag("en-US")
                        Text("Español").tag("es-ES")
                    }
                }
                Section("Line Alignment") {
                    Toggle("Align to Paper Lines", isOn: $assistant.alignToPaper)
                    LabeledContent("Letter Size", value: "\(Int((assistant.sizeScale * 100).rounded()))%")
                    Slider(value: $assistant.sizeScale, in: 0.7...1.3, step: 0.05).accessibilityLabel("Converted letter size")
                    LabeledContent("Baseline Adjustment", value: "\(assistant.baselineOffset.formatted(.number.precision(.fractionLength(0)))) pt")
                    Slider(value: $assistant.baselineOffset, in: -8...8, step: 1).accessibilityLabel("Baseline adjustment. Negative moves text up, positive moves text down.")
                    Button("Reset Alignment") { assistant.alignToPaper = true; assistant.sizeScale = 1; assistant.baselineOffset = 0 }
                    Text("Ruled, grid, dotted, lecture and Cornell writing areas use their paper guides. Blank pages and PDFs keep the original line position. Adjustments apply to your next conversion.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Convert Existing Handwriting", systemImage: "textformat") {
                        Task { await assistant.convertPage(session: session) }
                    }
                    .disabled(assistant.processing || session.busy || !session.ready)
                    if assistant.processing { ProgressView("Reading on this iPad…") }
                    Text(assistant.message).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityLabel("Handwriting status: \(assistant.message)")
                } footer: {
                    Text("Recognition runs locally. Cursive, equations and drawings may not be recognized correctly. Use Undo, or open converted text in Inserted Content to edit it or restore its original ink. Importing a personal font changes the letter style; it does not train recognition or create a font from a handwriting sample.")
                }
            }
            .navigationTitle("Handwriting Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
        .task { await loadFonts() }
        .fileImporter(isPresented: $showingFontImporter, allowedContentTypes: [.font], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    importing = true; defer { importing = false }
                    do {
                        let asset = try await HandwritingFontStore.shared.importFont(from: url, storage: session.storage)
                        await loadFonts()
                        assistant.fontFilePath = asset.path; assistant.fontName = asset.name
                    } catch { fontError = error.localizedDescription }
                }
            case .failure(let error): fontError = error.localizedDescription
            }
        }
        .alert("Could Not Load Font", isPresented: Binding(get: { fontError != nil }, set: { if !$0 { fontError = nil } })) {
            Button("OK") { fontError = nil }
        } message: { Text(fontError ?? "Your existing notes and fonts are preserved.") }
        .onChange(of: assistant.fontName) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
        .onChange(of: assistant.language) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
        .onChange(of: assistant.alignToPaper) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
        .onChange(of: assistant.sizeScale) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
        .onChange(of: assistant.baselineOffset) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
    }
    private func loadFonts() async {
        do {
            var assets = try await HandwritingFontStore.shared.catalog(storage: session.storage, including: session.elements)
            if let path = session.handwriting.fontFilePath {
                let selected = try await HandwritingFontStore.shared.load(path: path, storage: session.storage)
                if !assets.contains(where: { $0.name == selected.name }) { assets.append(selected) }
            }
            imported = assets
        } catch { fontError = error.localizedDescription }
    }
}
