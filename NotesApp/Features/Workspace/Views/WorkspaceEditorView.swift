import SwiftUI

/// Stable presentation slots keep native canvases alive through focus, resize and pane swaps.
struct WorkspaceEditorView: View {
    let workspace: DocumentWorkspace
    let focusMode: EditorFocusMode
    let showLibrary: () -> Void
    let toggleSidebar: () -> Void
    var preferencesDefaults: UserDefaults = .standard
    @State private var choosingDocument = false
    @GestureState private var dividerTranslation: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            if !focusMode.isActive {
                DocumentTabBar(workspace: workspace, showLibrary: showLibrary, toggleSidebar: toggleSidebar, showsRecents: false) {
                    splitControl
                }
            }
            GeometryReader { geometry in
                let horizontal = geometry.size.width >= 780
                let length = horizontal ? geometry.size.width : geometry.size.height
                let separator: CGFloat = workspace.isSplit && !focusMode.isActive ? 14 : 0
                let usable = max(0, length - separator)
                let translation = horizontal ? dividerTranslation.width : dividerTranslation.height
                let minimum = min(horizontal ? 320.0 : 280.0, usable / 2)
                let firstLength = min(usable - minimum, max(minimum, usable * workspace.splitFraction + translation))
                let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    ForEach(workspace.visiblePanes, id: \.self) { slot in
                      if let session = workspace.session(in: slot) {
                        let first = slot == workspace.visiblePanes.first
                        let hidden = focusMode.isActive && session !== workspace.activeSession
                        let size = !workspace.isSplit || focusMode.isActive ? (hidden ? 0 : length) : (first ? firstLength : usable - firstLength)
                        pane(session)
                            .frame(width: horizontal ? size : geometry.size.width,
                                   height: horizontal ? geometry.size.height : size)
                            .clipped().opacity(hidden ? 0 : 1).allowsHitTesting(!hidden).accessibilityHidden(hidden)
                        if first && workspace.isSplit {
                            divider(horizontal: horizontal, usable: usable, first: firstLength)
                                .frame(width: horizontal ? separator : geometry.size.width,
                                       height: horizontal ? geometry.size.height : separator)
                                .clipped().allowsHitTesting(!focusMode.isActive).accessibilityHidden(focusMode.isActive)
                        }
                      }
                    }
                }
            }
        }
        .background(AppTheme.background)
        .background(FocusSplitViewPolicy(focused: focusMode.isActive))
        .disabled(workspace.isSwitching)
        .sheet(isPresented: $choosingDocument) { SplitDocumentPicker(workspace: workspace) }
    }

    private func pane(_ session: EditorSession) -> some View {
        VStack(spacing: 0) {
            if workspace.isSplit && !focusMode.isActive {
                HStack(spacing: 8) {
                    Button { workspace.focus(session.notebook.id) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(workspace.activeID == session.notebook.id ? AppTheme.accent : .secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(session.notebook.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }
                    .accessibilityLabel("Focus \(session.notebook.title)")
                    .accessibilityAddTraits(workspace.activeID == session.notebook.id ? .isSelected : [])
                    Button { Task { _ = await workspace.close(session.notebook.id) } } label: {
                        Image(systemName: "xmark").font(.caption).frame(width: 44, height: 36)
                    }.accessibilityLabel("Close pane for \(session.notebook.title)")
                }.buttonStyle(.plain).padding(.leading, 16).background(AppTheme.headerBackground)
            }
            EditorView(session: session, onLibrary: showLibrary, workspace: workspace,
                       toggleSidebar: toggleSidebar, focusMode: focusMode,
                       preferencesDefaults: preferencesDefaults,
                       showsWorkspaceTabs: false, isSplitPane: workspace.isSplit)
                .onChange(of: session.page?.id) { _, _ in workspace.rememberCurrentPage() }
        }
        .accessibilityIdentifier("workspace.pane.\(session.notebook.id.uuidString)")
    }

    @ViewBuilder private var splitControl: some View {
        if workspace.isSplit {
            Menu {
                Button("Open Another Document Beside", systemImage: "doc.badge.plus") { choosingDocument = true }
                Button("Swap Panes", systemImage: "arrow.left.arrow.right") { workspace.swapPanes() }
                Button("Keep Focused Document Only", systemImage: "rectangle") { Task { _ = await workspace.closeSplit() } }
            } label: { Image(systemName: "rectangle.split.2x1.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("Split View Options").accessibilityIdentifier("workspace.split")
        } else {
            Button { choosingDocument = true } label: { Image(systemName: "rectangle.split.2x1").frame(width: 44, height: 44) }
                .accessibilityLabel("Open a Document Beside").accessibilityIdentifier("workspace.split")
        }
    }

    private func divider(horizontal: Bool, usable: CGFloat, first: CGFloat) -> some View {
        ZStack {
            AppTheme.background
            Capsule().fill(.secondary.opacity(0.35)).frame(width: horizontal ? 4 : 40, height: horizontal ? 40 : 4)
        }.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .updating($dividerTranslation) { value, state, _ in if !workspace.blocksNavigation { state = value.translation } }
                .onEnded { value in
                    let translation = horizontal ? value.translation.width : value.translation.height
                    let minimum = min(horizontal ? 320.0 : 280.0, usable / 2)
                    let proposed = min(usable - minimum, max(minimum, usable * workspace.splitFraction + translation))
                    if usable > 0 { workspace.setSplitFraction(proposed / usable) }
                })
            .accessibilityElement().accessibilityLabel("Document divider")
            .accessibilityValue("\(Int((usable > 0 ? first / usable : 0.5) * 100)) percent")
            .accessibilityAdjustableAction { direction in
                workspace.setSplitFraction(workspace.splitFraction + (direction == .increment ? 0.1 : -0.1))
            }
    }
}
