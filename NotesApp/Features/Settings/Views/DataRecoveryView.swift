import SwiftUI

struct DataRecoveryView: View {
    var body: some View {
        Form {
            Section("Make a recoverable copy") {
                Text("Open Settings → Backups → Create Library Backup. Wait for Files to confirm the save, and keep the .heynotesbackup file outside HeyNotes. A PDF export is useful for reading, but does not replace an editable library backup.")
                Text("Create another backup before changing devices, reinstalling, or deleting the app. Keep your previous copy until you have checked the new one.")
            }
            Section("Restore a library") {
                Text("Open Settings → Backups → Restore from Backup. Choose your file, check the verified preview, then restore. Existing notes stay intact; matching items become separate copies. Restoring the same backup again adds another copy.")
                Text("After restoring, check handwriting, PDFs, images, page order and flashcard source links. Close and reopen the app to check the saved result. Keep the original backup file.")
            }
            Section("Recover removed items") {
                Text("Restore notebooks and folders from Library → Trash, and study items from Study → Trash. For a removed page, open its notebook → Pages → Recently Deleted → Restore. Restoring the page preserves its original study links.")
                Text("Pages removed with older builds may have retained drawing files without recovery metadata. Recently Deleted cannot reconstruct those missing pages automatically. A backup made before removal may still contain them.")
            }
            Section("When a save or restore fails") {
                Text("Keep the app open if it shows unsaved handwriting. Use Retry Saving and make space through iPad Settings if storage is full. Avoid uninstalling the app or clearing its data to solve a save error.")
                Text("A missing or damaged file blocks a complete backup or restore with an error. Keep the original files and try another backup copy. A verification error does not authorize the app to erase existing notes.")
            }
            Section("Protect your backup") {
                Text("Backups are not password-protected. Keep them in a trusted location, allow space for both the archive and restored files, and check them periodically. Backups do not include open tabs, Undo history or tool preferences.")
            }
        }
        .navigationTitle("Data & Recovery").navigationBarTitleDisplayMode(.inline)
        .textSelection(.enabled)
    }
}
