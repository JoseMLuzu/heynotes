import SwiftUI

struct EditorElementDraft: Identifiable {
    let pageID: UUID
    let element: PageElement
    let isNew: Bool
    var id: UUID { element.id }
}

struct PageElementEditor: View {
    @State var draft: PageElement
    let pageSize: CGSize
    let save: (PageElement) -> Bool
    let remove: (() -> Void)?
    var restoreInk: (() -> Bool)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                if draft.kind == .text {
                    Section("Text") {
                        TextEditor(text: $draft.text).font(Font(HandwritingFont.resolve(draft.fontName, size: draft.fontSize))).frame(minHeight: 160)
                        Picker("Font", selection: Binding(get: { draft.fontName ?? "" }, set: { draft.fontName = $0.isEmpty ? nil : $0 })) {
                            Text("System").tag("")
                            ForEach(HandwritingFont.choices) { choice in
                                Text(choice.title).font(.custom(choice.name, size: 20)).tag(choice.name)
                            }
                        }
                        LabeledContent("Text Size", value: "\(Int(draft.fontSize))")
                        Slider(value: $draft.fontSize, in: 12...96, step: 1).accessibilityLabel("Text size")
                    }
                }
                if let restoreInk, draft.originalInk != nil {
                    Section {
                        Button("Restore Original Handwriting", systemImage: "pencil.tip") {
                            if restoreInk() { dismiss() } else { failed = true }
                        }
                    } footer: { Text("Replaces this text with its editable source strokes. You can undo this action.") }
                }
                if draft.kind != .tape && draft.kind != .image {
                    Section("Appearance") {
                        ColorPicker("Color", selection: Binding(get: { Color(red: draft.red, green: draft.green, blue: draft.blue) }, set: setColor), supportsOpacity: false)
                        if draft.kind != .text {
                            LabeledContent("Line Width", value: "\(draft.lineWidth.formatted(.number.precision(.fractionLength(0...1)))) pt")
                            Slider(value: $draft.lineWidth, in: 0.5...12).accessibilityLabel("Line width")
                        }
                    }
                }
                Section("Size and Position") {
                    slider("Width", value: $draft.width, range: 1...max(1, pageSize.width - draft.x))
                    slider("Height", value: $draft.height, range: 1...max(1, pageSize.height - draft.y))
                    slider("Horizontal Position", value: $draft.x, range: 0...max(1, pageSize.width - draft.width))
                    slider("Vertical Position", value: $draft.y, range: 0...max(1, pageSize.height - draft.height))
                    Text("You can also use Select Objects and drag the object or its corner handle on the page.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let remove {
                    Section { Button("Delete Object", role: .destructive) { confirmingDelete = true } }
                    .confirmationDialog("Delete this object?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { remove(); dismiss() }
                    } message: { Text("Use Undo in this page session to restore it. Image files are retained.") }
                }
            }
            .navigationTitle(draft.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if save(draft) { dismiss() } else { failed = true } }
                        .disabled(draft.kind == .text && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Could Not Save", isPresented: $failed) { Button("OK") {} } message: { Text("The object could not be saved. Your previous page content is preserved.") }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { Text(title).font(.subheadline); Slider(value: value, in: range).accessibilityLabel(title) }
    }
    private func setColor(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) {
            draft.red = max(0, min(1, r)); draft.green = max(0, min(1, g)); draft.blue = max(0, min(1, b))
        }
    }
}

struct InsertedContentView: View {
    @Bindable var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PageElement?
    var body: some View {
        NavigationStack {
            List {
                if session.elements.isEmpty { ContentUnavailableView("No Inserted Content", systemImage: "square.on.square", description: Text("Add text, an image, a shape or study tape from the editor tools.")) }
                ForEach(session.elements) { item in
                    Button { editing = item; session.selectedElementID = item.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind.title).foregroundStyle(.primary)
                            if item.kind == .text { Text(item.text).lineLimit(2).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Inserted Content").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { item in
                PageElementEditor(draft: item, pageSize: session.page?.logicalSize ?? PageGeometry.size) { updated in
                    var items = session.elements
                    guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return false }
                    items[index] = updated; return session.replaceElements(items)
                } remove: { _ = session.replaceElements(session.elements.filter { $0.id != item.id }, action: "Delete Object") }
                restoreInk: { session.restoreOriginalInk(item.id) }
            }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
    }
}
