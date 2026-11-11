import SwiftUI

struct ToolStripWidth: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ToolbarQuickControls: View {
    let preferences: ToolPreferences
    let session: EditorSession
    let inline: Bool
    var arrowEdge: Edge = .top
    let edit: (PageElement) -> Void
    @State private var showing = false

    var body: some View {
        Group {
            if inline {
                row
            } else {
                EditorMoreButton(title: "Quick Adjustments", identifier: "editor.quickAdjustments") { showing = true }
                .frame(width: 44, height: 44)
                .help("Quick colors, widths and object actions")
                .popover(isPresented: $showing, arrowEdge: arrowEdge) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preferences.selected.title).font(.headline)
                        row
                    }.padding(16).presentationCompactAdaptation(.popover)
                }
            }
        }
    }
    private var row: some View {
        QuickControlsRow(preferences: preferences, session: session) { item in
            showing = false; edit(item)
        }
    }
}

private struct QuickControlsRow: View {
    let preferences: ToolPreferences
    let session: EditorSession
    let edit: (PageElement) -> Void
    @State private var colorDraft: QuickColorDraft?
    @State private var deletion: ObjectTarget?
    @Environment(\.colorScheme) private var colorScheme
    private let widthNames = ["Fine", "Medium", "Thick"]
    private var widthColor: Color { colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8) }

    var body: some View {
        Group {
            if preferences.selected.usesInkStyle { inkControls }
            else if preferences.selected == .eraser { eraserControls }
            else if preferences.selected == .objects { objectControls }
            else {
                Text(preferences.selected == .tape ? "Draw with Pencil · Tap tape to reveal" : "Circle handwriting with the lasso")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 276, height: 44)
        .buttonStyle(EditorToolbarButtonStyle())
        .popover(item: $colorDraft) { draft in
            QuickColorEditor(color: draft.color) { color in
                guard preferences.selected == draft.tool else { return false }
                return preferences.setQuickColor(color, at: draft.index)
            }
        }
        .confirmationDialog("Delete this object?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible, presenting: deletion) { target in
            Button("Delete Object", role: .destructive) {
                guard session.page?.id == target.pageID else { return }
                _ = session.deleteElement(target.id)
            }
        } message: { _ in Text("You can undo this change on the current page. Image files are retained.") }
    }

    private var inkControls: some View {
        HStack(spacing: 0) {
            ForEach(0..<3) { index in
                let color = preferences.quickColors[index]
                let selected = preferences.matchesColor(color.color)
                Button { preferences.setColor(color.color) } label: {
                    Circle().fill(color.color).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(selected ? AppTheme.accent : .clear, lineWidth: 2).padding(8))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Favorite color \(index + 1)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("Favorite color \(index + 1). Touch and hold to customize.")
                .contextMenu {
                    Button("Customize Color", systemImage: "slider.horizontal.3") {
                        colorDraft = QuickColorDraft(index: index, tool: preferences.selected, color: color.color)
                    }
                }
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            ForEach(0..<3) { index in
                let width = preferences.quickWidths[index]
                let selected = abs(preferences.ink.width - width) < 0.01
                Button { preferences.ink.width = width } label: {
                    Capsule().fill(widthColor).frame(width: 18, height: CGFloat(2 + index * 2))
                        .frame(width: 44, height: 44)
                        .background(selected ? AppTheme.accent.opacity(0.12) : .clear, in: Circle())
                }
                .accessibilityLabel("\(widthNames[index]), \(width.formatted()) points")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("\(widthNames[index]) · \(width.formatted()) pt")
            }
        }
    }

    private var eraserControls: some View {
        HStack(spacing: 0) {
            ForEach([EraserMode.strokes, .precise], id: \.self) { mode in
                Button { preferences.eraserMode = mode } label: {
                    Image(systemName: mode == .strokes ? "scribble" : "eraser")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(preferences.eraserMode == mode ? AppTheme.accent : .secondary)
                        .background(preferences.eraserMode == mode ? AppTheme.accent.opacity(0.12) : .clear, in: Circle())
                }
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(preferences.eraserMode == mode ? .isSelected : [])
                .help(mode.title)
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            ForEach(0..<3) { index in
                let size = preferences.quickEraserSizes[index]
                let selected = abs(preferences.eraserWidth - size) < 0.01
                Button { preferences.eraserWidth = size } label: {
                    Circle().strokeBorder(widthColor, lineWidth: 1.5).frame(width: CGFloat(8 + index * 6), height: CGFloat(8 + index * 6))
                        .frame(width: 44, height: 44)
                        .background(selected ? AppTheme.accent.opacity(0.12) : .clear, in: Circle())
                }
                .disabled(preferences.eraserMode != .precise)
                .accessibilityLabel("Eraser size \(size.formatted()) points")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("\(size.formatted()) pt · Precise eraser")
            }
        }
    }

    private var objectControls: some View {
        HStack(spacing: 4) {
            Button {
                if let item = session.selectedElement { edit(item) }
            } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                .accessibilityLabel("Edit Selected Object").help("Edit selected object")
            Button {
                if let item = session.selectedElement { _ = session.duplicateElement(item.id) }
            } label: { Image(systemName: "plus.square.on.square").frame(width: 44, height: 44) }
                .accessibilityLabel("Duplicate Selected Object").help("Duplicate selected object")
            Button(role: .destructive) {
                if let item = session.selectedElement, let page = session.page {
                    deletion = ObjectTarget(id: item.id, pageID: page.id)
                }
            } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                .accessibilityLabel("Delete Selected Object").help("Delete selected object")
            Text("Select an object").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .opacity(session.selectedElement == nil ? 1 : 0)
                .accessibilityHidden(session.selectedElement != nil)
        }.disabled(session.selectedElement == nil)
    }
}

private struct ObjectTarget: Identifiable { let id: UUID; let pageID: UUID }
private struct QuickColorDraft: Identifiable {
    let index: Int
    let tool: EditorTool
    let color: Color
    var id: Int { index }
}

private struct QuickColorEditor: View {
    @State var color: Color
    let save: (Color) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Favorite Color").font(.headline)
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { if save(color) { dismiss() } else { failed = true } }
                    .fontWeight(.semibold)
            }.frame(minHeight: 44)
        }
        .padding(20).frame(width: 280).tint(AppTheme.accent)
        .presentationCompactAdaptation(.popover)
        .alert("Could Not Save Color", isPresented: $failed) { Button("OK") {} } message: {
            Text("Return to the original tool and try again.")
        }
    }
}
