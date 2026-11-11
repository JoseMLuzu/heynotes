import SwiftUI

/// Editing a draft never changes the active tool or a saved favorite until Save.
struct ToolPresetEditor: View {
    @State var draft: ToolPreset
    let save: (ToolPreset) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Favorite") {
                    TextField("Name", text: $draft.name)
                    Picker("Tool", selection: $draft.tool) {
                        ForEach(EditorTool.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                if draft.tool.usesInkStyle {
                    Section("Ink") {
                        ColorPicker("Color", selection: Binding(get: { draft.ink.color }, set: setColor), supportsOpacity: false)
                        LabeledContent("Width", value: "\(draft.ink.width.formatted(.number.precision(.fractionLength(0...1)))) pt")
                        Slider(value: $draft.ink.width, in: ToolPreset.widthRange(for: draft.tool))
                            .accessibilityLabel("Favorite stroke width")
                        LabeledContent("Opacity", value: "\(Int(draft.ink.opacity * 100))%")
                        Slider(value: $draft.ink.opacity, in: 0.1...1, step: 0.05).accessibilityLabel("Favorite ink opacity")
                    }
                } else if draft.tool == .eraser {
                    Section("Eraser") {
                        Picker("Mode", selection: $draft.eraserMode) {
                            ForEach(EraserMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if draft.eraserMode == .precise {
                            LabeledContent("Size", value: "\(draft.eraserWidth.formatted(.number.precision(.fractionLength(0...1)))) pt")
                            Slider(value: $draft.eraserWidth, in: ToolPreset.eraserRange).accessibilityLabel("Favorite eraser size")
                        }
                    }
                }
                Section {
                    Label(draft.tool.title, systemImage: draft.tool.symbol)
                        .foregroundStyle(draft.tool.usesInkStyle ? draft.ink.color : AppTheme.accent)
                    Text(draft.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if save(draft.sanitized) { dismiss() } }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: draft.tool) { _, _ in draft = draft.sanitized }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
    }
    private func setColor(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        draft.ink.red = red; draft.ink.green = green; draft.ink.blue = blue
    }
}
