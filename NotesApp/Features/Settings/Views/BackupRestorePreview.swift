import SwiftUI

struct BackupRestorePreview: View {
    let backup: PreparedLibraryBackup
    let busy: Bool
    let restore: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Created", value: backup.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Notebooks", value: "\(backup.manifest.notebooks.count)")
                    LabeledContent("Pages", value: "\(backup.manifest.pages.count)")
                    LabeledContent("Removed pages", value: "\(backup.manifest.pages.filter { $0.trashedAt != nil }.count)")
                    LabeledContent("Study decks", value: "\(backup.manifest.decks.count)")
                    LabeledContent("Study cards", value: "\(backup.manifest.cards.count)")
                    LabeledContent("Files", value: "\(backup.files.count)")
                    LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: Int64(clamping: backup.byteCount), countStyle: .file))
                } header: { Text("Verified Backup") }
                Section {
                    Text("Adds the backup to your library. Existing notes stay intact. Matching items are restored as separate copies, with their study links preserved.")
                    Text("Includes saved handwriting, PDFs, images, review history and items in Trash.")
                        .foregroundStyle(.secondary)
                    Button(action: restore) {
                        if busy { HStack { ProgressView(); Text("Restoring…") } }
                        else { Label("Restore Library", systemImage: "arrow.counterclockwise") }
                    }.disabled(busy).accessibilityIdentifier("backup.restore")
                }
            }
            .navigationTitle("Restore Backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel).disabled(busy) } }
        }
        .appSheetPresentation()
        .interactiveDismissDisabled(busy)
    }
}
