import SwiftUI

/// One set of tool controls, laid out horizontally or vertically for the selected edge.
struct EditorToolbar<InsertMenu: View>: View {
    @Bindable var preferences: ToolPreferences
    let session: EditorSession
    let quickPalette: QuickPalettePreferences
    let position: EditorToolbarPosition
    @Binding var showingToolOptions: Bool
    let edit: (PageElement) -> Void
    let openContent: () -> Void
    @ViewBuilder let insertMenu: InsertMenu
    @State private var toolStripWidth: CGFloat = 0
    @State private var presentedGroup: ToolbarToolGroup?

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
            quickPaletteButton
        }
        .padding(.vertical, 4)
        .frame(width: 52)
        .modifier(EditorGlassCapsule())
    }

    private var horizontalBar: some View {
        GeometryReader { geometry in
            // Keep tools first, then fill available room with direct adjustments. No overflow button.
            let slots = toolStripWidth > 0 ? ToolbarAdjustmentLayout.slots(
                fitting: geometry.size.width - toolStripWidth - 77, tool: preferences.selected) : 0
            let adjustmentWidth = slots > 0 ? ToolbarAdjustmentLayout.width(slots: slots) + 9 : 0
            let available = max(44, geometry.size.width - 77 - adjustmentWidth)
            let stripWidth = toolStripWidth > 0 ? min(toolStripWidth, available) : available
            HStack(spacing: 0) {
                Group {
                    if toolStripWidth > 0 && toolStripWidth <= available {
                        primaryTools.fixedSize(horizontal: true, vertical: false)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            primaryTools.background(ImmediateScrollTouchPolicy())
                        }
                    }
                }
                .frame(width: stripWidth, alignment: .leading)
                if slots > 0 {
                    Divider().frame(height: 24).padding(.horizontal, 4)
                    ToolbarQuickControls(preferences: preferences, session: session, slots: slots, edit: edit)
                }
                Divider().frame(height: 24).padding(.horizontal, 4)
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
        .padding(3)
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
        toolButton(.lasso)
        toolButton(.objects)
        separator
        ForEach(ToolbarToolGroup.allCases) { group in
            ToolbarToolGroupButton(group: group, preferences: preferences, page: session.page,
                                   arrowEdge: position.popoverEdge, presentedGroup: $presentedGroup) { tool in
                preferences.selected = tool
            }
        }
        separator
        toolButton(.laser)
        toolButton(.writingZoom)
        insertMenu
        separator
        strokeSettingsButton
    }

    private var separator: some View {
        Group {
            if position.isVertical { Divider().frame(width: 24).padding(.vertical, 3) }
            else { Divider().frame(height: 24) }
        }
    }

    private func toolButton(_ item: EditorTool) -> some View {
        Button {
            if item == .writingZoom, session.writingRegion != nil { Task { _ = await session.closeZoomWriting() } }
            else if preferences.selected == item { openToolSettings() }
            else { preferences.selected = item }
        } label: {
            ToolbarToolIcon(symbol: item.symbol,
                            active: preferences.selected == item || item == .writingZoom && session.writingRegion != nil)
        }
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("editor.tool.\(item.rawValue)")
        .accessibilityAddTraits(preferences.selected == item || item == .writingZoom && session.writingRegion != nil ? .isSelected : [])
        .accessibilityHint("Select this tool. Tap again for settings, or hold and drag to Quick Palette.")
        .modifier(PaletteToolDragSource(snapshot: { preferences.capturePreset(for: item) }, palette: quickPalette) {
            let stroke = (session.zoomCanvas ?? session.canvas)?.drawingGestureRecognizer.state
            return session.ready && !session.busy && !session.exporting && stroke != .began && stroke != .changed
        })
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
                HStack(spacing: 4) {
                    if preferences.selected.usesInkStyle {
                        Circle().fill(preferences.ink.color).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                        Text(preferences.ink.width, format: .number.precision(.fractionLength(0...1)))
                            .frame(width: 32, alignment: .trailing)
                    } else if preferences.selected == .eraser {
                        Image(systemName: preferences.eraserMode == .highlighter ? "highlighter" : "eraser").frame(width: 14)
                        Text(preferences.eraserMode == .strokes ? "—" : preferences.eraserWidth.formatted(.number.precision(.fractionLength(0...1))))
                            .frame(width: 32, alignment: .trailing)
                    } else {
                        Image(systemName: preferences.selected.symbol).frame(width: 50)
                    }
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 88, height: 44)
            }
        }
        .accessibilityLabel("\(preferences.selected.title) settings")
        .accessibilityValue(preferences.selected.usesInkStyle ? "\(preferences.ink.width.formatted()) points" : preferences.selected == .eraser ? preferences.eraserMode.title : "")
        .help("\(preferences.selected.title) settings")
        .popover(isPresented: $showingToolOptions, arrowEdge: position.popoverEdge) {
            ToolOptionsPanel(preferences: preferences) { session.clearHandwriting() }.tint(AppTheme.accent)
        }
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
