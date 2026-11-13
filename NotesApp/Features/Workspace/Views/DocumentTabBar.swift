import SwiftUI

struct DocumentTabBar<TrailingActions: View>: View {
    let workspace: DocumentWorkspace
    let showLibrary: () -> Void
    let toggleSidebar: () -> Void
    let showsRecents: Bool
    let backButton: NavigationBackButton?
    let trailingActions: TrailingActions
    init(workspace: DocumentWorkspace, showLibrary: @escaping () -> Void,
         toggleSidebar: @escaping () -> Void, showsRecents: Bool = true,
         backButton: NavigationBackButton? = nil,
         @ViewBuilder trailingActions: () -> TrailingActions) {
        self.workspace = workspace; self.showLibrary = showLibrary
        self.toggleSidebar = toggleSidebar; self.showsRecents = showsRecents
        self.backButton = backButton
        self.trailingActions = trailingActions()
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var minimumTabWidth: CGFloat = 140

    var body: some View {
        HStack(spacing: 8) {
            if let backButton {
                backButton.frame(height: rowHeight)
            } else {
                Button { if !workspace.blocksNavigation { toggleSidebar() } } label: {
                    Image(systemName: "sidebar.left")
                        .font(.body)
                        .frame(width: 44, height: rowHeight)
                }
                .accessibilityLabel("Toggle Sidebar")
                .accessibilityIdentifier("workspace.sidebar")
                .modifier(EditorGlassSurface(shape: Circle()))
                .help("Show or hide the library sidebar")
            }

            if workspace.openNotebooks.isEmpty {
                Spacer(minLength: 0)
            } else {
                tabStrip
            }
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        // Combined with the tool row's six-point inset, this leaves an eight-point gap.
        .padding(.bottom, 2)
        .background(AppTheme.headerBackground)
        .allowsHitTesting(!workspace.blocksTabControls)
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            GeometryReader { geometry in
                let count = max(1, workspace.openNotebooks.count)
                let width = max(minimumTabWidth, (geometry.size.width - CGFloat(count - 1) * 4) / CGFloat(count))
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 4) {
                            ForEach(workspace.openNotebooks) { notebook in
                                tab(notebook, width: width).id(notebook.id)
                            }
                        }
                    }
                    .onChange(of: workspace.activeID, initial: true) { _, id in
                        if let id {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(id) }
                        }
                    }
                    .onChange(of: geometry.size.width) { _, _ in
                        if let id = workspace.activeID { proxy.scrollTo(id) }
                    }
                    .onChange(of: workspace.openNotebooks.count) { _, _ in
                        if let id = workspace.activeID { proxy.scrollTo(id) }
                    }
                }
            }
            .frame(height: rowHeight)
            Button { if !workspace.blocksNavigation { showLibrary() } } label: {
                Group {
                    if workspace.isSwitching { ProgressView() }
                    else { Image(systemName: "plus") }
                }
                .frame(width: 44, height: rowHeight)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(workspace.isSwitching ? "Opening notebook" : "Open Another Notebook")
            .help("Open another notebook from Library")
            if showsRecents {
                Menu {
                    Section("Recently Opened") {
                        ForEach(workspace.recentNotebooks) { notebook in
                            Button(notebook.title) { Task { await workspace.open(notebook) } }
                        }
                        if workspace.recentNotebooks.isEmpty { Text("No Recent Notebooks") }
                    }
                } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: rowHeight) }
                .accessibilityLabel("Recently Opened Notebooks")
            }
            trailingActions
                .frame(height: rowHeight)
        }
        .padding(.horizontal, 4)
        .frame(height: rowHeight)
        .padding(.vertical, 4)
        .modifier(EditorGlassSurface(shape: RoundedRectangle(cornerRadius: 16)))
    }

    private func tab(_ notebook: Notebook, width: CGFloat) -> some View {
        let selected = workspace.activeID == notebook.id
        return HStack(spacing: 0) {
            Button { Task { await workspace.open(notebook) } } label: {
                HStack(spacing: 7) {
                    Capsule().fill(notebook.coverColor.color).frame(width: 3, height: 12)
                    Text(notebook.title).fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1).truncationMode(.tail)
                    if selected, let session = workspace.activeSession {
                        Circle()
                            .fill(session.hasPendingSave || !session.ready ? Color.orange : Color.blue)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                            .help(session.status)
                    }
                }
                .padding(.leading, 10)
                .frame(width: max(0, width - 44), height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Open \(notebook.title)")
            .accessibilityValue(selected ? workspace.activeSession?.status ?? "" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button { Task { await workspace.close(notebook.id) } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                    .frame(width: 44, height: rowHeight).contentShape(Rectangle())
            }
            .accessibilityLabel("Close tab for \(notebook.title)")
            .accessibilityHint("Keeps the notebook in your library.")
        }
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10).fill(AppTheme.accent.opacity(0.12))
                    .frame(height: rowHeight - 6)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(notebook.coverColor.color).frame(height: 2).padding(.horizontal, 12)
                    }
            }
        }
    }
}
