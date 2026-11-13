import SwiftUI

struct NotebookIndexView: View {
    @Bindable var session: EditorSession
    let close: () -> Void
    @State private var bookmarksOnly: Bool
    @State private var naming: NameAction?
    @State private var title = ""
    @State private var deleting: NotebookSection?
    @State private var deletingPageID: UUID?
    init(session: EditorSession, bookmarksOnly: Bool = false, close: @escaping () -> Void) {
        self.session = session
        self.close = close
        _bookmarksOnly = State(initialValue: bookmarksOnly)
    }
    private enum NameAction {
        case section, rename(UUID), bookmark(UUID)
        var heading: String { switch self { case .section: "New Section"; case .rename: "Rename Section"; case .bookmark: "Page Bookmark" } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(bookmarksOnly ? "Bookmarks" : "Pages").font(.headline)
                Spacer()
                Button { bookmarksOnly.toggle() } label: {
                    Label(bookmarksOnly ? "All Pages" : "Bookmarks", systemImage: bookmarksOnly ? "square.grid.2x2" : "bookmark")
                        .font(.caption.weight(.medium)).frame(minHeight: 44)
                }
                .accessibilityLabel(bookmarksOnly ? "Show all pages" : "Show bookmarked pages")
                Menu {
                    Button("New Section", systemImage: "folder.badge.plus") { title = ""; naming = .section }
                    Button("Add Page", systemImage: "plus") { Task { await session.addPage(); if session.ready { close() } } }
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add page or section")
                Button("Done", action: close).frame(minHeight: 44)
            }.padding(.horizontal, 12)
            HStack {
                Button { Task { await session.turnPage(-1) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(session.page?.pageIndex == 0).accessibilityLabel("Previous page")
                Spacer()
                Text("\((session.page?.pageIndex ?? 0) + 1) / \(session.notebook.pages.count)").font(.subheadline.monospacedDigit())
                Spacer()
                Button { Task { await session.turnPage(1) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(session.page?.pageIndex == session.notebook.pages.count - 1).accessibilityLabel("Next page")
            }.padding(.horizontal, 8)
            if let page = session.page {
                Button {
                    title = page.bookmarkTitle ?? "Page \(page.pageIndex + 1)"
                    naming = .bookmark(page.id)
                } label: {
                    Label(page.bookmarkTitle == nil ? "Bookmark This Page" : "Edit Page Bookmark",
                          systemImage: page.bookmarkTitle == nil ? "bookmark" : "bookmark.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .background(AppTheme.accent.opacity(0.08))
                .disabled(!session.ready)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if bookmarksOnly {
                        let pages = session.notebook.orderedPages.filter { $0.bookmarkTitle != nil }
                        if pages.isEmpty { ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Use Bookmark This Page above to keep this page close.")) }
                        pageGrid(pages)
                    } else {
                        ForEach(session.notebook.orderedSections) { section in
                            HStack {
                                Text(section.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Menu {
                                    Button("Rename") { title = section.title; naming = .rename(section.id) }
                                    Button("Move Earlier") { session.moveSection(section, offset: -1) }.disabled(section.sortIndex == 0)
                                    Button("Move Later") { session.moveSection(section, offset: 1) }.disabled(section.sortIndex == session.notebook.sections.count - 1)
                                    Button("Move Current Page Here") { if let page = session.page { session.assign(page, to: section) } }
                                    Button("Delete Section", role: .destructive) { deleting = section }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(section.title)")
                            }
                            let pages = session.notebook.orderedPages.filter { $0.section?.id == section.id }
                            if pages.isEmpty { Text("No pages yet. Move a page here from its menu.").font(.caption).foregroundStyle(.secondary) }
                            pageGrid(pages)
                        }
                        if !session.notebook.sections.isEmpty { Text("Unsectioned Pages").font(.subheadline.weight(.semibold)) }
                        pageGrid(session.notebook.orderedPages.filter { $0.section == nil })
                    }
                }.padding(16)
            }
        }
        .buttonStyle(.plain).tint(AppTheme.accent)
        .allowsHitTesting(!session.busy)
        .frame(width: 360, height: 520)
        .presentationCompactAdaptation(.popover)
        .alert(naming?.heading ?? "Name", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            if let action = naming {
                TextField("Name", text: $title)
                Button("Cancel", role: .cancel) { naming = nil }
                if case .bookmark(let id) = action, let page = session.notebook.pages.first(where: { $0.id == id }), page.bookmarkTitle != nil {
                    Button("Remove Bookmark", role: .destructive) { _ = session.bookmark(page, title: nil) }
                }
                Button("Save") { saveName(action) }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .confirmationDialog("Delete this section?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { section in
            Button("Delete Section", role: .destructive) { session.deleteSection(section) }
        } message: { _ in Text("Its pages will remain in this notebook under Unsectioned Pages.") }
        .confirmationDialog("Delete this page?", isPresented: Binding(
            get: { deletingPageID != nil }, set: { if !$0 { deletingPageID = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) {
                if let id = deletingPageID, let page = session.notebook.pages.first(where: { $0.id == id }) {
                    Task { await session.deletePage(page) }
                }
                deletingPageID = nil
            }
            Button("Cancel", role: .cancel) { deletingPageID = nil }
        } message: { Text("The page will be removed from this notebook. Its drawing file is retained locally for recovery.") }
        .alert("Could Not Update Notebook", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }
    private func pageGrid(_ pages: [NotePage]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 12)], spacing: 16) {
            ForEach(pages) { page in
                Button {
                    Task { await session.open(page); if session.ready, session.page?.id == page.id { close() } }
                } label: {
                    VStack(spacing: 4) {
                        PageThumbnail(page: page, notebookID: session.notebook.id, selected: page.id == session.page?.id)
                        if let name = page.bookmarkTitle { Label(name, systemImage: "bookmark.fill").font(.caption2).lineLimit(2) }
                    }.frame(minWidth: 76, minHeight: 108)
                }
                .contextMenu {
                    Button(page.bookmarkTitle == nil ? "Add Bookmark" : "Rename Bookmark", systemImage: "bookmark") { title = page.bookmarkTitle ?? ""; naming = .bookmark(page.id) }
                    if page.bookmarkTitle != nil { Button("Remove Bookmark") { _ = session.bookmark(page, title: nil) } }
                    Menu("Move to Section", systemImage: "folder") {
                        Button("Unsectioned Pages") { session.assign(page, to: nil) }
                        ForEach(session.notebook.orderedSections) { section in Button(section.title) { session.assign(page, to: section) } }
                    }
                    Divider()
                    Button("Duplicate Page", systemImage: "plus.square.on.square") { Task { await session.duplicatePage(page) } }
                        .disabled(!session.ready)
                    Button("Move Page Earlier", systemImage: "arrow.left") { session.movePage(-1, target: page) }
                        .disabled(page.pageIndex == 0)
                    Button("Move Page Later", systemImage: "arrow.right") { session.movePage(1, target: page) }
                        .disabled(page.pageIndex == session.notebook.pages.count - 1)
                    Button("Delete Page", systemImage: "trash", role: .destructive) { deletingPageID = page.id }
                        .disabled(session.notebook.pages.count <= 1)
                }
            }
        }
    }
    private func saveName(_ action: NameAction) {
        switch action {
        case .section: _ = session.createSection(title)
        case .rename(let id): if let section = session.notebook.sections.first(where: { $0.id == id }) { _ = session.renameSection(section, title: title) }
        case .bookmark(let id): if let page = session.notebook.pages.first(where: { $0.id == id }) { _ = session.bookmark(page, title: title) }
        }
    }
}
