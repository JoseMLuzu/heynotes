import SwiftUI

/// A fixed index anchored to the page counter. Thumbnails, rather than the panel, can be moved.
struct NotebookPagesPanel: View {
    let session: EditorSession
    let close: () -> Void

    var body: some View {
        NotebookIndexView(session: session, close: close)
            .frame(width: 380, height: 520)
            .presentationCompactAdaptation(.popover)
    }
}
