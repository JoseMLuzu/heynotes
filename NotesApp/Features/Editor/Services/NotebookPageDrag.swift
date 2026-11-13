import CoreTransferable
import UniformTypeIdentifiers
import SwiftUI

/// Carries permanent references only. Drawing/PDF files never travel through drag and drop.
struct NotebookPageDrag: Codable, Transferable, Sendable, Equatable {
    let notebookID: UUID
    let pageID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .notebookPageReference)
            .visibility(.ownProcess)
    }
}

extension UTType {
    static let notebookPageReference = UTType(exportedAs: "com.local.notesapp.page-reference", conformingTo: .data)
}

/// Apply to each complete thumbnail tile so gaps inside a tile also accept a drop.
struct NotebookPageReordering: ViewModifier {
    let session: EditorSession
    let pageID: UUID
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .draggable(NotebookPageDrag(notebookID: session.notebook.id, pageID: pageID))
            .dropDestination(for: NotebookPageDrag.self) { items, _ in
                guard items.count == 1, let source = items.first else { return false }
                return session.reorderPage(source, onto: pageID)
            } isTargeted: { targeted = $0 }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
                    .opacity(targeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .accessibilityHint("Touch and hold, then drag onto another page to change its order. Move Earlier and Move Later are also available in the page menu.")
    }
}
