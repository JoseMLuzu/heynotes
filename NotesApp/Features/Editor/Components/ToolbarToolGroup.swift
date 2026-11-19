import SwiftUI

/// Stable homes for tools; browsing a group never changes the current drawing tool.
enum ToolbarToolGroup: String, CaseIterable, Identifiable {
    case drawing, study, capture
    var id: String { rawValue }
    var fullTitle: String { switch self { case .drawing: "Draw and Measure"; case .study: "Study Tools"; case .capture: "Capture Tools" } }
    var symbol: String { switch self { case .drawing: "square.on.circle"; case .study: "graduationcap"; case .capture: "viewfinder" } }
    var tools: [EditorTool] {
        switch self {
        case .drawing: [.line, .rectangle, .ellipse, .arrow, .protractor, .compass]
        case .study: [.tape, .sticky, .stamp, .cardCapture]
        case .capture: [.capture, .pdfHighlight]
        }
    }
    func contains(_ tool: EditorTool) -> Bool { tools.contains(tool) }
    static func isAvailable(_ tool: EditorTool, on page: NotePage?) -> Bool {
        tool != .pdfHighlight || page?.pdfFilePath != nil
    }
    static func title(for tool: EditorTool) -> String {
        switch tool {
        case .cardCapture: "Flashcard"
        case .pdfHighlight: "PDF Highlight"
        case .capture: "Capture Region"
        default: tool.title
        }
    }
}

struct ToolbarToolGroupButton: View {
    let group: ToolbarToolGroup
    let preferences: ToolPreferences
    let page: NotePage?
    let arrowEdge: Edge
    @Binding var presentedGroup: ToolbarToolGroup?
    let palette: QuickPalettePreferences
    let canInteract: () -> Bool
    let select: (EditorTool) -> Void

    private var active: Bool { group.contains(preferences.selected) }
    var body: some View {
        Button { presentedGroup = presentedGroup == group ? nil : group } label: {
            ToolbarToolIcon(symbol: active ? preferences.selected.symbol : group.symbol, active: active)
        }
        .accessibilityLabel(group.fullTitle)
        .accessibilityIdentifier("editor.tools.\(group.rawValue)")
        .accessibilityValue(active ? preferences.selected.title : "Choose a tool")
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(group.fullTitle)
        .accessibilityHint(active ? "Tap to choose a tool, or hold and drag the selected tool to Quick Palette." : "Tap to choose a tool.")
        .modifier(PaletteToolDragSource(snapshot: { preferences.capturePreset() }, palette: palette,
                                       canInteract: { active && canInteract() }))
        .popover(isPresented: Binding(get: { presentedGroup == group }, set: { if !$0, presentedGroup == group { presentedGroup = nil } }), arrowEdge: arrowEdge) {
            ToolbarToolGroupPanel(group: group, preferences: preferences, page: page, palette: palette, canInteract: canInteract,
                                 dismissForDrag: { presentedGroup = nil }) { tool in
                presentedGroup = nil; select(tool)
            }
            .tint(AppTheme.accent)
        }
    }
}

struct ToolbarToolIcon: View {
    let symbol: String
    var active = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .regular))
        .foregroundStyle(active ? AppTheme.accent : .secondary)
        .frame(width: 44, height: 44)
        .background(active ? AppTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ToolbarToolGroupPanel: View {
    let group: ToolbarToolGroup
    @Bindable var preferences: ToolPreferences
    let page: NotePage?
    let palette: QuickPalettePreferences
    let canInteract: () -> Bool
    var dismissForDrag: (() -> Void)? = nil
    let select: (EditorTool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(group.fullTitle, systemImage: group.symbol).font(.headline)
                Spacer()
                Button("Done") { dismiss() }.frame(minHeight: 44)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(group.tools, id: \.self) { tool in
                    let selected = preferences.selected == tool
                    Button { select(tool) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: tool.symbol).font(.system(size: 23))
                            Text(ToolbarToolGroup.title(for: tool)).font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                        .foregroundStyle(selected ? AppTheme.accent : .primary)
                        .frame(maxWidth: .infinity).frame(minHeight: 76)
                        .background(selected ? AppTheme.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? AppTheme.accent.opacity(0.35) : .clear))
                    }
                    .disabled(!ToolbarToolGroup.isAvailable(tool, on: page))
                    .accessibilityLabel(tool.title)
                    .accessibilityIdentifier("editor.tool.\(tool.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help(tool.guidance)
                    .accessibilityHint("Select this tool, or hold and drag it to Quick Palette.")
                    .modifier(PaletteToolDragSource(snapshot: { preferences.capturePreset(for: tool) }, palette: palette,
                        canInteract: { canInteract() && ToolbarToolGroup.isAvailable(tool, on: page) }, didPrepareDrag: {
                            // Return the immutable provider to UIKit before removing its popover anchor.
                            Task { @MainActor in
                                await Task.yield()
                                if let dismissForDrag { dismissForDrag() } else { dismiss() }
                            }
                        }))
                }
            }
            if group == .drawing {
                Divider()
                Toggle("Ruler", systemImage: "ruler", isOn: $preferences.rulerEnabled).frame(minHeight: 44)
                Toggle("Hold to Snap Shapes", systemImage: "scribble.variable", isOn: $preferences.smartShapes).frame(minHeight: 44)
            }
            if group == .study {
                Text("Choose a tool, then tap or draw on the page. Change its style with the toolbar settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if group == .capture {
                Text("Draw a region with Apple Pencil. PDF highlighting requires a PDF page with selectable text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Hold and drag a tool onto a Quick Palette favorite to replace it, or onto + to add it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 320)
        .buttonStyle(EditorToolbarButtonStyle())
        .presentationCompactAdaptation(.popover)
    }
}
