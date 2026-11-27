import SwiftUI

struct RemovedPagesView: View {
    @Bindable var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These pages stay in this notebook until you restore them. Their handwriting, PDFs and study links are kept. There is no automatic expiration.")
                        .foregroundStyle(.secondary)
                }
                if session.notebook.removedPages.isEmpty {
                    ContentUnavailableView("No Removed Pages", systemImage: "trash", description: Text("Pages you remove from this notebook will appear here."))
                } else {
                    ForEach(session.notebook.removedPages) { page in
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            PageThumbnail(page: page, notebookID: session.notebook.id, selected: false, storage: session.storage)
                                .frame(width: 64, height: 88).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.bookmarkTitle ?? "Page \(page.pageIndex + 1)").font(.headline)
                                if let date = page.trashedAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Button("Restore") { Task { await session.restorePage(page) } }
                                .buttonStyle(.bordered).frame(minHeight: 44).disabled(session.busy)
                                .accessibilityLabel("Restore \(page.bookmarkTitle ?? "page \(page.pageIndex + 1)")")
                                .accessibilityIdentifier("page.restore.\(page.id)")
                        }
                    }
                }
            }
            .navigationTitle("Recently Deleted").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(session.busy) } }
            .alert("Could Not Restore Page", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
        .appSheetPresentation()
        .interactiveDismissDisabled(session.busy)
    }
}
