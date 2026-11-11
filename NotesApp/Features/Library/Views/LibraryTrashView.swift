import SwiftUI

struct LibraryTrashView: View {
    let model: LibraryViewModel

    var body: some View {
        if model.trashedFolders.isEmpty && model.trashedNotebooks.isEmpty {
            ContentUnavailableView("Nothing in Trash", systemImage: "trash", description: Text("Removed folders and notebooks stay here until you restore them."))
        } else {
            List {
                Section {
                    Text("Restore a folder to return its contents to their original locations. Previously removed items remain in Trash.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !model.trashedFolders.isEmpty {
                    Section("Folders") {
                        ForEach(model.trashedFolders) { folder in
                            HStack {
                                Label(folder.pathTitle, systemImage: "folder")
                                Spacer()
                                Button("Restore") { model.restore(folder) }.frame(minHeight: 44)
                            }
                        }
                    }
                }
                if !model.trashedNotebooks.isEmpty {
                    Section("Notebooks & PDFs") {
                        ForEach(model.trashedNotebooks) { notebook in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(notebook.title).font(.headline)
                                    Text("\(notebook.pages.count) pages · \(notebook.folder?.pathTitle ?? "Inbox")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") { model.restore(notebook) }.frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
    }
}
