import SwiftUI
import SwiftData

struct SplitDocumentPicker: View {
    let workspace: DocumentWorkspace
    @State private var notebooks: [Notebook] = []
    @State private var search = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(notebooks.filter { search.isEmpty || $0.title.localizedStandardContains(search) }) { notebook in
                        Button {
                            Task {
                                if await workspace.openBeside(notebook) { dismiss() }
                                else {
                                    error = workspace.errorMessage ?? "The document could not be opened. Check the other pane for a save error."
                                    workspace.errorMessage = nil
                                }
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(notebook.title).foregroundStyle(.primary)
                                    Text("\(notebook.pages.count) pages").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: notebook.pages.contains { $0.pdfFilePath != nil } ? "doc.richtext" : "book.closed")
                                    .foregroundStyle(notebook.coverColor.color)
                            }
                        }.disabled(workspace.blocksNavigation)
                    }
                } footer: { Text("The focused document stays open. Your selection opens in the other pane.") }
                if notebooks.isEmpty {
                    ContentUnavailableView("No other documents", systemImage: "rectangle.split.2x1",
                                           description: Text("Create another notebook or import a PDF in Library, then open it beside this document."))
                }
            }
            .searchable(text: $search, prompt: "Find a notebook or PDF")
            .navigationTitle("Open Beside").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Could Not Open Document", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .appSheetPresentation()
        .task {
            do {
                let visible = Set(workspace.visibleSessions.map { $0.notebook.id })
                notebooks = try workspace.context.fetch(FetchDescriptor<Notebook>(sortBy: [SortDescriptor(\.title)]))
                    .filter { !$0.isInTrash && !visible.contains($0.id) }
            } catch { self.error = error.localizedDescription }
        }
    }
}
