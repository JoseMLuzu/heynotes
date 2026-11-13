import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

private enum LibrarySheet: Identifiable {
    case notebook(PaperTemplate), folder(UUID?), renameNotebook(Notebook), renameFolder(Folder)
    var id: String {
        switch self {
        case .notebook: "new-notebook"
        case .folder(let id): "new-folder-\(id?.uuidString ?? "root")"
        case .renameNotebook(let item): "notebook-\(item.id)"
        case .renameFolder(let item): "folder-\(item.id)"
        }
    }
}

struct LibraryView: View {
    @State private var model: LibraryViewModel
    @State private var navigation: LibraryNavigation
    @State private var search = ""
    @AppStorage("library.sortOrder") private var sortOrder: LibrarySortOrder = .recent
    @State private var workspace: DocumentWorkspace
    @State private var focusMode: EditorFocusMode
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingImporter = false
    @State private var importing = false
    @State private var sheet: LibrarySheet?
    @State private var pendingTemplate: PaperTemplate?
    @State private var showingTemplateGallery = false
    @State private var deletingNotebook: Notebook?
    @State private var deletingFolder: Folder?
    @State private var changingCover: Notebook?
    @State private var coloringFolder: Folder?
    @State private var showingSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openingSource: DocumentOpeningSource?
    @State private var isOpeningDocument = false

    init(context: ModelContext, workspace: DocumentWorkspace? = nil, focusMode: EditorFocusMode? = nil,
         navigation: LibraryNavigation? = nil, columnVisibility: NavigationSplitViewVisibility = .automatic) {
        _model = State(initialValue: LibraryViewModel(context: context))
        _navigation = State(initialValue: navigation ?? LibraryNavigation())
        _workspace = State(initialValue: workspace ?? DocumentWorkspace(context: context))
        _focusMode = State(initialValue: focusMode ?? EditorFocusMode())
        _columnVisibility = State(initialValue: columnVisibility)
    }

    // Focus overrides presentation, retaining the user's normal layout for restoration.
    private var focusColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { focusMode.isActive ? .detailOnly : columnVisibility },
                set: { if !focusMode.isActive { columnVisibility = $0 } })
    }
    private var focusCompactColumn: Binding<NavigationSplitViewColumn> {
        Binding(get: { focusMode.isActive ? .detail : compactColumn },
                set: { if !focusMode.isActive { compactColumn = $0 } })
    }

    private var selectedFolder: Folder? { navigation.folder(in: model.folders) }
    private var backDestination: String? { navigation.backDestination(in: model.folders) }

    private var title: String {
        switch navigation.selection {
        case .favorites: "Favorites"
        case .study: "Study"
        case .inbox: "Inbox"
        case .trash: "Trash"
        case .folder: selectedFolder?.title ?? "Folder"
        default: "Library"
        }
    }

    private var visibleNotebooks: [Notebook] {
        model.notebooks.filter { notebook in
            let matchesSection: Bool
            switch navigation.selection {
            case .favorites: matchesSection = notebook.isFavorite
            case .folder(let id): matchesSection = notebook.folder?.id == id
            case .inbox: matchesSection = notebook.folder == nil
            case .library: matchesSection = !search.isEmpty || notebook.folder == nil
            default: matchesSection = false
            }
            return matchesSection && (search.isEmpty || notebook.title.localizedStandardContains(search))
        }
    }

    private var visibleFolders: [Folder] {
        model.folders.filter { folder in
            let matches: Bool
            switch navigation.selection {
            case .favorites: matches = folder.isFavorite
            case .folder(let id): matches = folder.parent?.id == id
            case .library: matches = !search.isEmpty || folder.parent == nil
            default: matches = false
            }
            return matches && (search.isEmpty || folder.title.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: focusColumnVisibility, preferredCompactColumn: focusCompactColumn) {
            List(selection: Binding(get: { navigation.selection }, set: { destination in
                Task {
                    if await workspace.showLibrary() {
                        navigation.selection = destination ?? .library; model.reload()
                        if sizeClass == .compact { compactColumn = .detail }
                    }
                }
            })) {
                Section {
                    Label("Library", systemImage: "books.vertical").tag(LibrarySection.library)
                    Label("Favorites", systemImage: "star").tag(LibrarySection.favorites)
                    Label("Study", systemImage: "rectangle.on.rectangle").tag(LibrarySection.study)
                }
                Section {
                    Button {
                        Task { if await workspace.showLibrary() { model.reload(); showingTemplateGallery = true } }
                    } label: { Label("Templates", systemImage: "square.stack.3d.up") }
                }
                Section("Library") {
                    Label("Inbox", systemImage: "tray").tag(LibrarySection.inbox)
                    OutlineGroup(model.folders.filter { $0.parent == nil }, children: \.visibleChildren) { folder in
                        FolderSidebarLabel(folder: folder, selected: navigation.selection == .folder(folder.id))
                            .tag(LibrarySection.folder(folder.id))
                            .contextMenu { folderActions(folder) }
                    }
                    Button { sheet = .folder(nil) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                }
                Section { Label("Trash", systemImage: "trash").tag(LibrarySection.trash) }
                Section {
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Write. Study. Remember.").font(.system(.footnote, design: .serif)).foregroundStyle(.secondary)
                        Label("On this iPad", systemImage: "internaldrive")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .allowsHitTesting(!workspace.blocksTabControls)
            .navigationTitle("Notes")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: toggleSidebar) { Image(systemName: "sidebar.left") }
                            .accessibilityLabel("Close Sidebar")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    if workspace.activeSession == nil && (!workspace.openNotebooks.isEmpty || backDestination != nil) {
                        DocumentTabBar(workspace: workspace, showLibrary: showLibrary, toggleSidebar: toggleSidebar,
                                       backButton: NavigationBackButton(destination: backDestination, action: goBack)) { EmptyView() }
                    }
                    if workspace.activeSession == nil {
                        AppTheme.headerBackground.frame(height: 16).accessibilityHidden(true)
                    }
                    Group {
                        if let session = workspace.activeSession {
                            EditorView(session: session, onLibrary: showLibrary, workspace: workspace, toggleSidebar: toggleSidebar, focusMode: focusMode)
                                .onChange(of: session.page?.id) { _, _ in workspace.rememberCurrentPage() }
                                .disabled(workspace.isSwitching)
                                .transition(openingTransition(for: session.notebook.id))
                                .zIndex(1)
                        } else if navigation.selection == .trash {
                            LibraryTrashView(model: model)
                        } else if navigation.selection == .study {
                            ContentUnavailableView("A little practice. A lasting memory.", systemImage: "rectangle.on.rectangle",
                                                   description: Text("Study is coming soon. Your notebooks are ready for the ideas you want to keep."))
                        } else {
                            libraryContent
                                .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(openingAnimation, value: workspace.activeID)
                }
                .onChange(of: workspace.activeID) { _, id in
                    focusMode.exit()
                    if openingSource?.id != id { openingSource = nil }
                }
                .background(AppTheme.background)
                .navigationTitle(workspace.activeSession == nil ? title : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(AppTheme.headerBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar(workspace.activeSession == nil ? .visible : .hidden, for: .navigationBar)
                .toolbar {
                    if workspace.activeSession == nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: toggleSidebar) { Image(systemName: "sidebar.left") }
                                .accessibilityLabel("Toggle Sidebar")
                                .accessibilityIdentifier("library.sidebar")
                        }
                    }
                    if navigation.selection != .study && navigation.selection != .trash && workspace.activeSession == nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showingImporter = true } label: { Label("Import PDF", systemImage: "square.and.arrow.down") }
                                .disabled(importing)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button { sheet = .folder(selectedFolder?.id) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button { sheet = .notebook(AppPreferences.shared.defaultPaper) } label: { Label("New Notebook", systemImage: "plus") }
                        }
                    }
                }
            }
        }
        .task { await workspace.restore() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            workspace.activeSession?.discardPreparedPages()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { workspace.backgroundSave() } }

        .overlay {
            if importing { ProgressView("Importing PDF…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }
        .disabled(importing || model.isWorking || workspace.isSwitching)
        .allowsHitTesting(!isOpeningDocument)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                let folder = selectedFolder
                importing = true
                Task { await model.importPDF(from: url, folder: folder); importing = false }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showingTemplateGallery, onDismiss: {
            if let template = pendingTemplate { pendingTemplate = nil; sheet = .notebook(template) }
        }) {
            TemplateGallery { template in pendingTemplate = template }
        }
        .sheet(isPresented: $showingSettings) { AppSettingsView() }
        .sheet(item: $coloringFolder) { folder in
            FolderColorPicker(folder: folder) { model.changeColor(folder, to: $0) }
        }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .notebook(let template):
                    NotebookForm(folders: model.folders.sorted { $0.pathTitle < $1.pathTitle }, initialFolderID: selectedFolder?.id, initialTemplate: template) { title, cover, template, folder in
                        model.createNotebook(title: title, color: cover.accentColor, template: template, folder: folder, cover: cover)
                    }
                case .folder(let parentID):
                    TitleForm(heading: parentID == nil ? "New Folder" : "New Subfolder", title: "") {
                        model.createFolder(title: $0, parent: model.folders.first { $0.id == parentID })
                    }
                case .renameNotebook(let notebook):
                    TitleForm(heading: "Rename Notebook", title: notebook.title) { model.rename(notebook, title: $0) }
                case .renameFolder(let folder):
                    TitleForm(heading: "Rename Folder", title: folder.title) { model.rename(folder, title: $0) }
                }
            }
            .alert("Could Not Save", isPresented: errorPresented) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
        .fullScreenCover(item: $changingCover) { notebook in
            CoverGallery(current: notebook.coverStyle, title: notebook.title) { model.changeCover(notebook, to: $0) }
                .alert("Could Not Save", isPresented: errorPresented) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
        .alert("Library Error", isPresented: Binding(
            get: { (model.errorMessage != nil || workspace.errorMessage != nil) && sheet == nil && changingCover == nil && coloringFolder == nil && !showingSettings },
            set: { if !$0 { model.errorMessage = nil; workspace.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil; workspace.errorMessage = nil }
        } message: { Text(model.errorMessage ?? workspace.errorMessage ?? "") }
        .confirmationDialog("Move notebook to Trash?", isPresented: Binding(
            get: { deletingNotebook != nil }, set: { if !$0 { deletingNotebook = nil } }
        ), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let notebook = deletingNotebook {
                    Task { if await workspace.forget(notebook.id) { model.delete(notebook) } }
                }
                deletingNotebook = nil
            }
        } message: { Text("This notebook and its \(deletingNotebook?.pages.count ?? 0) pages will move to Trash. You can restore them later.") }
        .confirmationDialog("Move folder and contents to Trash?", isPresented: Binding(
            get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }
        ), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let folder = deletingFolder {
                    let ids = Set(model.documents(inSubtreeOf: folder).map(\.id))
                    Task {
                        if await workspace.forget(ids) { model.delete(folder); navigation.selection = .library }
                    }
                }
                deletingFolder = nil
            }
        } message: { Text(folderTrashMessage) }
    }

    private var openingAnimation: Animation? {
        guard !reduceMotion, openingSource?.id == workspace.activeID,
              openingSource != nil else { return nil }
        return .easeOut(duration: DocumentOpeningZoom.duration)
    }

    private func openingTransition(for id: UUID) -> AnyTransition {
        guard !reduceMotion, let source = openingSource, source.id == id else { return .identity }
        return .modifier(active: DocumentOpeningZoom(sourceFrame: source.frame, progress: 0),
                         identity: DocumentOpeningZoom(sourceFrame: source.frame, progress: 1))
    }

    private func openFromLibrary(_ notebook: Notebook, from frame: CGRect?) {
        guard !workspace.blocksNavigation else { return }
        if let frame, frame.width > 0, frame.height > 0, !reduceMotion {
            openingSource = DocumentOpeningSource(id: notebook.id, frame: frame)
        } else { openingSource = nil }
        isOpeningDocument = openingSource != nil
        Task {
            guard await workspace.open(notebook) else {
                openingSource = nil; isOpeningDocument = false; return
            }
            // Do not accept Pencil strokes against a surface still moving into place.
            if isOpeningDocument { try? await Task.sleep(for: .seconds(DocumentOpeningZoom.duration + 0.02)) }
            isOpeningDocument = false
        }
    }

    private func toggleSidebar() {
        if sizeClass == .compact {
            compactColumn = compactColumn == .sidebar ? .detail : .sidebar
        } else {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func showLibrary() {
        Task { if await workspace.showLibrary() { model.reload() } }
    }

    private func goBack() {
        guard !workspace.blocksNavigation, backDestination != nil else { return }
        navigation.goBack(in: model.folders)
        search = ""
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var libraryContent: some View {
        let notebooks = sortOrder.sortedNotebooks(visibleNotebooks)
        let folders = sortOrder.sortedFolders(visibleFolders, allFolders: model.folders, notebooks: model.notebooks)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    Text(navigation.selection == .favorites ? "Keep a few close." : selectedFolder != nil ? "Ideas, in good company." : "A place for your thoughts.")
                        .font(.system(.title3, design: .serif, weight: .medium))
                    Spacer(minLength: 12)
                    if !notebooks.isEmpty {
                        Text("\(notebooks.count) \(notebooks.count == 1 ? "notebook" : "notebooks")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    sortMenu
                }
                if notebooks.isEmpty && folders.isEmpty {
                    if !search.isEmpty {
                        ContentUnavailableView.search(text: search).frame(minHeight: 320)
                    } else if navigation.selection == .favorites {
                        LibraryEmptyState(title: "Keep your favorites nearby.",
                                          message: "Touch and hold a folder or notebook, then add it to Favorites.",
                                          actionTitle: "View Library") { navigation.selection = .library }
                    } else {
                        LibraryEmptyState(title: "Every idea starts somewhere.",
                                          message: "A lecture, a question, a thought worth keeping. Give it a notebook.",
                                          actionTitle: "Create Notebook") { sheet = .notebook(AppPreferences.shared.defaultPaper) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 28, alignment: .top)], spacing: 30) {
                        ForEach(folders) { folder in
                            Button { navigation.open(folder) } label: { FolderCard(folder: folder) }
                                .buttonStyle(QuietPressStyle())
                                .hoverEffect(.lift)
                                .contextMenu { folderActions(folder) }
                        }
                        ForEach(notebooks) { notebook in
                            LibraryNotebookTile(notebook: notebook, storage: model.storage) { frame in
                                openFromLibrary(notebook, from: frame)
                            }
                            .contextMenu { notebookMenu(notebook) }
                        }
                    }
                }
            }
            .background(ImmediateScrollTouchPolicy())
            .padding(32)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $search, prompt: "Search notebooks")
    }

    private var sortMenu: some View {
        let actions = LibrarySortOrder.allCases.map { order in
            UIAction(title: order.title, state: order == sortOrder ? .on : .off) { _ in
                sortOrder = order
            }
        }
        return EditorMoreButton(title: "Sort Library", identifier: "library.sort", symbol: "arrow.up.arrow.down",
                                menu: UIMenu(title: "Sort by", options: .singleSelection, children: actions))
            .frame(width: 44, height: 44)
            .accessibilityValue(sortOrder.title)
            .help("Sort by name, latest changes or document type")
    }

    private var folderTrashMessage: String {
        guard let folder = deletingFolder else { return "" }
        let ids = folder.subtreeIDs
        let subfolders = model.folders.filter { ids.contains($0.id) && $0.id != folder.id }.count
        let documents = model.documents(inSubtreeOf: folder).count
        return "This folder, \(subfolders) subfolders and \(documents) documents will move to Trash. Restore the folder to recover its contents."
    }

    private func folderActions(_ folder: Folder) -> some View {
        FolderActionsMenu(folder: folder, model: model,
                          newSubfolder: { sheet = .folder(folder.id) },
                          rename: { sheet = .renameFolder(folder) },
                          changeColor: { coloringFolder = folder },
                          trash: { deletingFolder = folder })
    }

    @ViewBuilder
    private func notebookMenu(_ notebook: Notebook) -> some View {
        if !notebook.pages.contains(where: { $0.pdfFilePath != nil }) {
            Button("Change Cover", systemImage: "book.closed") { changingCover = notebook }
        }
        Button("Rename", systemImage: "pencil") { sheet = .renameNotebook(notebook) }
        Button(notebook.isFavorite ? "Remove Favorite" : "Add to Favorites", systemImage: "star") { model.toggleFavorite(notebook) }
        Button("Duplicate", systemImage: "plus.square.on.square") { Task { await model.duplicate(notebook) } }
        Menu("Move to Folder", systemImage: "folder") {
            Button("Inbox") { model.move(notebook, to: nil) }
            ForEach(model.folders) { folder in
                Button(folder.pathTitle) { model.move(notebook, to: folder) }
            }
        }
        Button("Move to Trash", systemImage: "trash", role: .destructive) { deletingNotebook = notebook }
    }
}
