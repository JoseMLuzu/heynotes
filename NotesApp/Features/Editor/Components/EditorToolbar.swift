import SwiftUI

/// One set of tool controls, laid out horizontally or vertically for the selected edge.
struct EditorToolbar<InsertMenu: View>: View {
    @Bindable var preferences: ToolPreferences
    let session: EditorSession
    let quickPalette: QuickPalettePreferences
    let position: EditorToolbarPosition
    let edit: (PageElement) -> Void
    let openContent: () -> Void
    @ViewBuilder let insertMenu: InsertMenu
    @State private var showingToolOptions = false
    @State private var toolStripWidth: CGFloat = 0

    var body: some View {
        Group {
            if position.isVertical { verticalBar }
            else { horizontalBar }
        }
        .buttonStyle(EditorToolbarButtonStyle())
        .disabled(!session.ready)
        .allowsHitTesting(!session.busy)
    }

    private var verticalBar: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                primaryTools.background(ImmediateScrollTouchPolicy())
            }
            Divider().frame(width: 24).padding(.vertical, 4)
            ToolbarQuickControls(preferences: preferences, session: session, inline: false,
                                 arrowEdge: position.popoverEdge, edit: edit)
            quickPaletteButton
        }
        .padding(.vertical, 4)
        .frame(width: 52)
        .modifier(EditorGlassCapsule())
    }

    private var horizontalBar: some View {
        GeometryReader { geometry in
            let inline = toolStripWidth > 0 && geometry.size.width >= toolStripWidth + 354
            // 78 pt of padding/dividers/palette, plus 276 pt inline or 44 pt overflow.
            let available = geometry.size.width - (inline ? 354 : 122)
            HStack(spacing: 0) {
                Group {
                    // Keep only one live control tree and one anchor per popover.
                    if toolStripWidth > 0 && toolStripWidth <= available {
                        primaryTools.fixedSize(horizontal: true, vertical: false)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            primaryTools.background(ImmediateScrollTouchPolicy())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider().frame(height: 24).padding(.horizontal, 4)
                // Keep every primary tool visible before using the spare width for adjustments.
                ToolbarQuickControls(preferences: preferences, session: session,
                                     inline: inline) { item in
                    edit(item)
                }
                Divider().frame(height: 24)
                quickPaletteButton.padding(.horizontal, 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .modifier(EditorGlassCapsule())
            .disabled(!session.ready)
            .allowsHitTesting(!session.busy)
            .onPreferenceChange(ToolStripWidth.self) { width in
                if abs(toolStripWidth - width) > 0.5 { toolStripWidth = width }
            }
        }
        .frame(height: 52)
    }

    private var primaryTools: some View {
        Group {
            if position.isVertical {
                VStack(spacing: 2) { primaryButtons }
            } else {
                HStack(spacing: 2) { primaryButtons }
            }
        }
        .padding(4)
        .background {
            if !position.isVertical {
                GeometryReader { content in
                    Color.clear.preference(key: ToolStripWidth.self, value: content.size.width)
                }
            }
        }
    }

    @ViewBuilder private var primaryButtons: some View {
        ForEach([EditorTool.pen, .pencil, .marker, .eraser], id: \.self) { toolButton($0) }
        strokeSettingsButton
        separator
        toolButton(.lasso)
        toolButton(.objects)
        separator
        shapesMenu
        toolButton(.tape)
        insertMenu
    }

    private var separator: some View {
        Group {
            if position.isVertical { Divider().frame(width: 24).padding(.vertical, 3) }
            else { Divider().frame(height: 24) }
        }
    }

    private func toolButton(_ item: EditorTool) -> some View {
        Button {
            if preferences.selected == item { openToolSettings() }
            else { preferences.selected = item }
        } label: {
            Image(systemName: item.symbol).frame(width: 44, height: 44)
                .foregroundStyle(preferences.selected == item ? AppTheme.accent : .secondary)
                .background {
                    if preferences.selected == item {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.12))
                    }
                }
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(preferences.selected == item ? .isSelected : [])
        .accessibilityHint("Select this tool. Tap again for settings.")
    }

    private func openToolSettings() {
        if preferences.selected == .objects { openContent() }
        else { showingToolOptions = true }
    }

    private var strokeSettingsButton: some View {
        Button(action: openToolSettings) {
            if position.isVertical {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            } else {
                HStack(spacing: 6) {
                    ZStack {
                        // The readout keeps its width when switching tools as well as numbers.
                        HStack(spacing: 6) {
                            Circle().frame(width: 16, height: 16)
                            Text("\(88.8.formatted(.number.precision(.fractionLength(1)))) pt")
                        }
                        .hidden().accessibilityHidden(true)
                        if preferences.selected.usesInkStyle {
                            HStack(spacing: 6) {
                                Circle().fill(preferences.ink.color).frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                                Text("\(preferences.ink.width.formatted(.number.precision(.fractionLength(0...1)))) pt")
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        } else {
                            Text(preferences.selected == .eraser ? "Eraser" : preferences.selected == .tape ? "Tape" : "Selection")
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .font(.caption.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "slider.horizontal.3")
                }
                .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
            }
        }
        .accessibilityLabel("\(preferences.selected.title) settings")
        .popover(isPresented: $showingToolOptions, arrowEdge: position.popoverEdge) {
            ToolOptionsPanel(preferences: preferences) { session.clearHandwriting() }.tint(AppTheme.accent)
        }
    }

    private var shapesMenu: some View {
        Menu {
            ForEach([EditorTool.line, .rectangle, .ellipse, .arrow], id: \.self) { tool in
                Button(tool.title, systemImage: tool.symbol) { preferences.selected = tool }
            }
            Divider()
            Toggle("Ruler", systemImage: "ruler", isOn: $preferences.rulerEnabled)
        } label: {
            Image(systemName: preferences.selected.elementKind != nil && preferences.selected != .tape ? preferences.selected.symbol : "square.on.circle")
                .frame(width: 44, height: 44)
                .foregroundStyle(preferences.selected.usesInkStyle && preferences.selected.inkType == nil ? AppTheme.accent : .secondary)
        }.accessibilityLabel("Shapes, arrows and ruler")
    }

    private var quickPaletteButton: some View {
        let expanded = quickPalette.isVisible && !quickPalette.isCollapsed
        return Button { quickPalette.togglePresentation() } label: {
            Image(systemName: "paintpalette")
                .foregroundStyle(expanded ? AppTheme.accent : .secondary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(expanded ? "Hide Quick Palette" : "Show Quick Palette")
        .accessibilityAddTraits(expanded ? .isSelected : [])
        .help(expanded ? "Hide Quick Palette" : "Show Quick Palette")
        .contextMenu {
            Button("Restore Quick Palette", systemImage: "arrow.counterclockwise") {
                quickPalette.place(PalettePosition()); quickPalette.show()
            }
        }
    }
}
