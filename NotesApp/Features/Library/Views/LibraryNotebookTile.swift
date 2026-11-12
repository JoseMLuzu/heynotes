import SwiftUI

/// Geometry is needed only when opening a document, not as observable library state.
@MainActor final class NotebookOpeningFrame {
    var rect: CGRect?
}

struct LibraryNotebookTile: View {
    let notebook: Notebook
    let storage: DrawingStorage
    let open: (CGRect?) -> Void
    @State private var openingFrame: NotebookOpeningFrame

    init(notebook: Notebook, storage: DrawingStorage, openingFrame: NotebookOpeningFrame = NotebookOpeningFrame(),
         open: @escaping (CGRect?) -> Void) {
        self.notebook = notebook; self.storage = storage; self.open = open
        _openingFrame = State(initialValue: openingFrame)
    }

    var body: some View {
        let id = notebook.id
        Button { open(openingFrame.rect) } label: { NotebookCard(notebook: notebook, storage: storage) }
            .buttonStyle(QuietPressStyle())
            .hoverEffect(.lift)
            .onPreferenceChange(NotebookCoverFrames.self) { frames in
                openingFrame.rect = frames[id]
            }
    }
}
