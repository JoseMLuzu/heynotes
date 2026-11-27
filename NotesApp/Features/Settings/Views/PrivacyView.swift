import SwiftUI

/// Offline information for the current local-only build. No remote policy is loaded.
struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Label("Your notes belong to you", systemImage: "hand.raised")
                    .font(.headline)
                Text("This version of HeyNotes works on your iPad without an account. It does not send your notes or study activity to the developer.")
            }
            Section("What stays on this iPad") {
                Text("Notebooks, handwriting, imported PDFs and images, fonts, flashcards and review history are stored in the app’s local storage. Appearance, tools and open-document preferences are also saved locally.")
                Text("Optional handwriting conversion uses Apple’s on-device Vision framework. Recognition can make mistakes; keep and review your original handwriting.")
            }
            Section("Collection and tracking") {
                Text("HeyNotes includes no advertising, tracking, third-party analytics or automatic upload of notes or diagnostics to the developer. It does not request your location, contacts or full photo library.")
                Text("When you choose a photo or file, the system picker gives the app access to your selection. Sharing and exporting happen only when you choose them.")
            }
            Section("Backups and sharing") {
                Text("A library backup contains private notes and editable files. It is not password-protected or encrypted by HeyNotes. Save it somewhere you trust and choose recipients carefully.")
                Text("Files providers, sharing destinations and iPad backups are managed by you and the services you select. For example, a backup you save to iCloud Drive may be uploaded by that service. This is separate from notebook sync, which is not enabled in this version.")
            }
            Section("Retention and deletion") {
                Text("Removed notebooks, folders and study items stay in Trash. Removed pages stay in Recently Deleted inside their notebook’s Pages panel. They are retained for recovery; moving an item there does not permanently erase its data.")
                Text("Deleting the app can remove its local library. Export a complete library backup first. Copies you exported or shared remain in their destinations until you delete them there.")
            }
            Section("Your choices") {
                Text("You can use the app offline, disable handwriting conversion, export PDFs and editable backups, and restore removed items. No account deletion request is needed because HeyNotes has no accounts.")
                Text("Apple may handle system diagnostics or device backups according to your device settings and Apple’s policies.")
            }
        }
        .navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
        .textSelection(.enabled)
    }
}
