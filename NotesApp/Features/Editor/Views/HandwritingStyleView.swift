import SwiftUI

struct HandwritingStyleView: View {
    @Bindable var session: EditorSession
    @Environment(\.dismiss) private var dismiss

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
                    Picker("Handwritten Font", selection: $assistant.fontName) {
                        ForEach(HandwritingFont.choices) { choice in
                            Text(choice.title).font(.custom(choice.name, size: 20)).tag(choice.name)
                        }
                    }
                    Text("Write. Study. Remember.")
                        .font(.custom(assistant.fontName, size: 30))
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .accessibilityLabel("Font preview: Write. Study. Remember.")
                    Picker("Recognition Language", selection: $assistant.language) {
                        Text("English").tag("en-US")
                        Text("Español").tag("es-ES")
                    }
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
                    Text("Recognition runs locally. Check the result: cursive, equations and drawings may not be recognized correctly. Use Undo, or open the converted text in Inserted Content to edit it or restore its original ink. Your personal handwriting font is not supported yet.")
                }
            }
            .navigationTitle("Handwriting Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
        .onChange(of: assistant.fontName) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
        .onChange(of: assistant.language) { assistant.reset(to: session.canvas?.drawing ?? session.drawing) }
    }
}
