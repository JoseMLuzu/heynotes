import SwiftUI
import SwiftData
import PencilKit
import PhotosUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Bindable var session: EditorSession
    let onLibrary: () -> Void
    var workspace: DocumentWorkspace? = nil
    var toggleSidebar: (() -> Void)? = nil
    let showsWorkspaceTabs: Bool
    let isSplitPane: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var controls: EditorControlPreferences
    private var preferences: ToolPreferences { controls.tools }
    private var quickPalette: QuickPalettePreferences { controls.palette }
    @State private var focusMode: EditorFocusMode
    @State private var toolbarPlacement: EditorToolbarPreferences
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .caption) private var pageControlWidth: CGFloat = 68
    @State private var fingerDrawing = false
    @State private var deleting = false
    @State private var showingPages = false
    @State private var showingTemplates = false
    @State private var sharedPDF: SharedPDF?
    @State private var editingContent: EditorElementDraft?
    @State private var showingContent = false
    @State private var showingHandwritingStyle = false
    @State private var showingToolOptions = false
    @State private var showingMargin = false
    @State private var studySource: StudySource?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingImageFile = false


    init(session: EditorSession, onLibrary: @escaping () -> Void,
         workspace: DocumentWorkspace? = nil, toggleSidebar: (() -> Void)? = nil,
         toolbarPlacement: EditorToolbarPreferences? = nil, focusMode: EditorFocusMode? = nil,
         palette: QuickPalettePreferences? = nil, preferencesDefaults: UserDefaults = .standard,
         controls: EditorControlPreferences? = nil,
         showsWorkspaceTabs: Bool = true, isSplitPane: Bool = false) {
        self.session = session; self.onLibrary = onLibrary
        self.workspace = workspace; self.toggleSidebar = toggleSidebar
        self.showsWorkspaceTabs = showsWorkspaceTabs; self.isSplitPane = isSplitPane
        _toolbarPlacement = State(initialValue: toolbarPlacement ?? EditorToolbarPreferences.shared)
        _focusMode = State(initialValue: focusMode ?? EditorFocusMode())
        _controls = StateObject(wrappedValue: controls ?? EditorControlPreferences(defaults: preferencesDefaults, palette: palette))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if session.ready {
                    EditorCanvasContent(session: session, tools: preferences, fingerDrawing: fingerDrawing,
                                        onPencilDoubleTap: handlePencilDoubleTap,
                                        onInteraction: { workspace?.focus(session.notebook.id) })
                        // Give the new notebook its own canvas without rebuilding the toolbar and tabs.
                        .id(session.notebook.id)
                        .allowsHitTesting(!session.busy)
                } else if session.busy {
                    ProgressView("Opening page…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Page Could Not Be Opened", systemImage: "doc.badge.exclamationmark")
                    } description: { Text("Your files are preserved. Retry loading or restore the last checkpoint.") } actions: {
                        Button("Retry") { if let page = session.page { Task { await session.open(page) } } }
                        Button("Restore Backup") { Task { await session.recover() } }
                    }
                }
            }
        }
        .overlay {
            if (session.ready && quickPalette.isVisible) || focusMode.isActive {
                QuickPalette(palette: quickPalette, tools: preferences,
                             onExitFocus: focusMode.isActive ? { focusMode.exit() } : nil) {
                    let stroke = session.canvas?.drawingGestureRecognizer.state
                    return session.ready && !session.busy && stroke != .began && stroke != .changed
                }
                .allowsHitTesting(focusMode.isActive || !session.busy)
            }
        }
        .background(AppTheme.background)
        .overlay {
            if session.exporting { ProgressView("Preparing PDF…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(focusMode.isActive)
        .persistentSystemOverlays(focusMode.isActive ? .hidden : .automatic)
        .background(FocusSplitViewPolicy(focused: focusMode.isActive && (workspace == nil || showsWorkspaceTabs)))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !focusMode.isActive && toolbarPlacement.position == .bottom {
                toolBar.frame(height: 52).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(uiColor: AppTheme.canvasUIColor))
            }
        }
        .safeAreaInset(edge: .leading, spacing: 0) {
            if !focusMode.isActive && toolbarPlacement.position == (layoutDirection == .leftToRight ? .left : .right) { sideToolbar }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if !focusMode.isActive && toolbarPlacement.position == (layoutDirection == .leftToRight ? .right : .left) { sideToolbar }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !focusMode.isActive {
                VStack(spacing: 0) {
                    if showsWorkspaceTabs, let workspace {
                        DocumentTabBar(workspace: workspace, showLibrary: onLibrary,
                                       toggleSidebar: toggleSidebar ?? onLibrary, showsRecents: false) {
                            pageOptions.labelStyle(.iconOnly).frame(width: 44, height: 44)
                        }
                    }
                    editorHeader
                }
            }
        }
        .fullScreenCover(isPresented: $showingTemplates) {
            TemplateGallery(current: session.page?.paperTemplate ?? .blank) { session.changeTemplate($0) }
        }
        .sheet(item: $editingContent) { draft in
            PageElementEditor(draft: draft.element, pageSize: session.page?.logicalSize ?? PageGeometry.size, save: { value in
                guard session.page?.id == draft.pageID else { return false }
                let success = draft.isNew ? session.insertElement(value) : session.updateElement(value)
                if success { preferences.selected = .objects }
                return success
            }, remove: nil, restoreInk: { session.restoreOriginalInk(draft.element.id) })
        }
        .sheet(isPresented: $showingContent) { InsertedContentView(session: session) }
        .sheet(isPresented: $showingHandwritingStyle) { HandwritingStyleView(session: session) }
        .background(alignment: .topTrailing) {
            if focusMode.isActive {
                Color.clear.frame(width: 1, height: 1)
                    .popover(isPresented: $showingToolOptions, arrowEdge: .top) {
                        ToolOptionsPanel(preferences: preferences) { session.clearHandwriting() }.tint(AppTheme.accent)
                    }
            }
        }
        .onAppear { session.handwriting.setTool(preferences.selected, session: session) }
        .onChange(of: session.notebook.id) { _, _ in
            resetDocumentControls()
            session.handwriting.setTool(preferences.selected, session: session)
        }
        .onChange(of: preferences.selected) { _, value in session.handwriting.setTool(value, session: session) }
        .onChange(of: focusMode.isActive) { _, active in if active { showingPages = false } }
        .onDisappear { session.handwriting.cancel() }
        .sheet(isPresented: $showingMargin) { PDFMarginEditor(session: session) }
        .sheet(item: $studySource) { source in
            StudyCaptureView(context: session.context, source: source)
        }
        .photosPicker(isPresented: $showingPhotos, selection: $selectedPhoto, matching: .images)
        .fileImporter(isPresented: $showingImageFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else {
                if case .failure(let error) = result { session.errorMessage = error.localizedDescription }; return
            }
            let pageID = session.page?.id
            Task {
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try Data(contentsOf: url)
                    }.value
                    guard canFinishImport else { return }
                    guard session.page?.id == pageID else { session.errorMessage = "Return to the original page before inserting this image."; return }
                    if await session.addImage(data) { preferences.selected = .objects }
                } catch { session.errorMessage = error.localizedDescription }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            let pageID = session.page?.id
            Task {
                defer {
                    if isCurrentSession, selectedPhoto == item { selectedPhoto = nil }
                }
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        guard canFinishImport, selectedPhoto == item else { return }
                        guard session.page?.id == pageID else { session.errorMessage = "Return to the original page before inserting this image."; return }
                        if await session.addImage(data) { preferences.selected = .objects }
                    }
                } catch { session.errorMessage = "The image could not be imported. \(error.localizedDescription)" }
            }
        }
        .sheet(item: $sharedPDF) { item in PDFShareSheet(url: item.url) }
        .alert("Notebook Needs Attention", isPresented: Binding(get: { session.errorMessage != nil && !showingMargin && !showingContent && !showingPages && editingContent == nil }, set: { if !$0 { session.errorMessage = nil } })) {
            if session.hasPendingSave {
                Button("Retry Saving") { Task { _ = await session.flush() } }
            }
            Button("OK") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .confirmationDialog("Delete this page?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) { Task { await session.deletePage() } }
        } message: { Text("The page will be removed from this notebook. Its drawing file is retained locally for recovery.") }
    }

    private var isCurrentSession: Bool { workspace == nil || workspace?.contains(session) == true }
    private var canFinishImport: Bool { isCurrentSession && workspace?.isSwitching != true }

    private func handlePencilDoubleTap(_ action: UIPencilPreferredAction) {
        guard isCurrentSession, workspace == nil || workspace?.activeSession === session,
              session.ready, !session.busy, !session.exporting,
              workspace?.isSwitching != true, session.errorMessage == nil,
              !showingPages, !showingTemplates, !showingContent,
              !showingHandwritingStyle, !showingMargin, !showingPhotos, !showingImageFile, studySource == nil,
              editingContent == nil, sharedPDF == nil, !deleting,
              let result = controls.performPencilAction(action) else { return }
        switch result {
        case .toolChanged: showingToolOptions = false
        case .toolOptions: showingToolOptions.toggle()
        case .contextualPalette:
            if focusMode.isActive { showingToolOptions.toggle() }
            else { quickPalette.togglePresentation() }
        }
    }

    private func resetDocumentControls() {
        fingerDrawing = false
        deleting = false
        showingPages = false
        showingTemplates = false
        sharedPDF = nil
        editingContent = nil
        showingContent = false
        showingHandwritingStyle = false
        showingToolOptions = false
        showingMargin = false
        studySource = nil
        selectedPhoto = nil
        showingPhotos = false
        showingImageFile = false
    }

    private var editorHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if !isSplitPane { Button(action: onLibrary) {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to Library")
                .modifier(EditorGlassSurface(shape: Circle()))
                .allowsHitTesting(!session.busy)
                }

                if isSplitPane || sizeClass == .compact || toolbarPlacement.position != .top {
                    Spacer(minLength: 0)
                } else {
                    toolBar.frame(minWidth: 44, maxWidth: .infinity).frame(height: 52)
                }

                HStack(spacing: 0) {
                    Group {
                        Button { session.canvas?.undoManager?.undo() } label: {
                            Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                        }.accessibilityLabel("Undo")
                        Button { session.canvas?.undoManager?.redo() } label: {
                            Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44)
                        }.accessibilityLabel("Redo")
                    }
                    .disabled(!session.ready)
                    Divider().frame(height: 20).padding(.horizontal, 4)
                    bookmarkButton
                    pageControls
                    if workspace == nil || !showsWorkspaceTabs {
                        pageOptions.labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .modifier(EditorGlassCapsule())
                .allowsHitTesting(!session.busy)

            }
            // Narrow iPad windows keep all actions at the top without squeezing the tools.
            if (isSplitPane || sizeClass == .compact) && toolbarPlacement.position == .top { toolBar.frame(height: 52) }
        }
        .buttonStyle(EditorToolbarButtonStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.headerBackground)
        .simultaneousGesture(TapGesture().onEnded { workspace?.focus(session.notebook.id) })
    }

    private var bookmarkButton: some View {
        let marked = session.page?.bookmarkTitle != nil
        return Button {
            if let page = session.page {
                _ = session.bookmark(page, title: marked ? nil : "Page \(page.pageIndex + 1)")
            }
        } label: {
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(marked ? "Remove bookmark from this page" : "Bookmark this page")
        .accessibilityValue(session.page?.bookmarkTitle ?? "Current page is not bookmarked")
        .accessibilityAddTraits(marked ? .isSelected : [])
        .help(marked ? "Remove this page's bookmark" : "Bookmark this page")
        .disabled(!session.ready)
        .allowsHitTesting(!session.busy)
    }

    private var pageOptions: some View {
        EditorMoreButton(title: "Page Options", identifier: "editor.pageOptions", menu: EditorPageMenu(
            session: session, workspace: workspace, palette: quickPalette,
            placement: toolbarPlacement, fingerDrawing: fingerDrawing,
            setFingerDrawing: { fingerDrawing = $0 }, present: { destination in
                switch destination {
                case .focus:
                    workspace?.focus(session.notebook.id)
                    focusMode.enter(documentID: session.notebook.id)
                case .content: showingContent = true
                case .margin: showingMargin = true
                case .templates: showingTemplates = true
                case .delete: deleting = true
                case .flashcard:
                    Task {
                        guard let page = session.page, await session.flush(), isCurrentSession,
                              session.page?.id == page.id else { return }
                        studySource = StudySource(notebookID: session.notebook.id, pageID: page.id)
                    }
                }
            }, share: { sharedPDF = SharedPDF(url: $0) }
        ).make())
        .frame(width: 44, height: 44)
        .disabled(session.busy)
    }

    private var pageControls: some View {
        Button { showingPages.toggle() } label: {
            Text("\((session.page?.pageIndex ?? 0) + 1) / \(session.notebook.pages.count)")
                .font(.system(.caption, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .frame(width: pageControlWidth, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Page \((session.page?.pageIndex ?? 0) + 1) of \(session.notebook.pages.count). Show all pages")
        .accessibilityIdentifier("editor.pages")
        .help("Show pages and bookmarks")
        .popover(isPresented: $showingPages, arrowEdge: .top) {
            NotebookPagesPanel(session: session) { showingPages = false }
        }
        .allowsHitTesting(!session.busy)
    }

    private func navigatePage(_ offset: Int) {
        let pages = session.notebook.orderedPages
        guard let index = pages.firstIndex(where: { $0.id == session.page?.id }),
              pages.indices.contains(index + offset) else { return }
        Task { await session.open(pages[index + offset]) }
    }

    private var sideToolbar: some View {
        GeometryReader { geometry in
            toolBar
                .frame(height: min(620, geometry.size.height))
                .frame(maxHeight: .infinity)
        }
        .frame(width: 52)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(uiColor: AppTheme.canvasUIColor))
    }

    private var toolBar: some View {
        EditorToolbar(preferences: preferences, session: session, quickPalette: quickPalette,
                      position: toolbarPlacement.position, showingToolOptions: $showingToolOptions, edit: { item in
            guard let page = session.page else { return }
            editingContent = EditorElementDraft(pageID: page.id, element: item, isNew: false)
        }, openContent: { showingContent = true }) {
            insertMenu
        }
    }

    private var insertMenu: some View {
        Menu {
            Button(session.handwriting.enabled ? "Handwriting Style · On" : "Handwriting Style", systemImage: "textformat") {
                showingHandwritingStyle = true
            }
            Divider()
            Button("Text", systemImage: "textformat") {
                guard let page = session.page else { return }
                let size = page.logicalSize
                let element = PageElement(kind: .text, rect: CGRect(x: min(24, size.width / 4), y: min(24, size.height / 4), width: min(320, size.width * 0.75), height: min(160, size.height * 0.75)))
                editingContent = EditorElementDraft(pageID: page.id, element: element, isNew: true)
            }
            Button("Image from Photos", systemImage: "photo") { showingPhotos = true }
            Button("Image from Files", systemImage: "folder") { showingImageFile = true }
            Button("Edit Inserted Content", systemImage: "square.and.pencil") { showingContent = true }
        } label: {
            Image(systemName: session.handwriting.enabled ? "textformat" : "plus.square")
                .foregroundStyle(session.handwriting.enabled ? AppTheme.accent : .primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(session.handwriting.enabled ? "Insert content. Handwriting Style is on" : "Insert content and handwriting style")
    }

}
