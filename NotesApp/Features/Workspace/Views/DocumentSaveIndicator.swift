import SwiftUI

/// One fixed-width status control for the focused document, independent of tab title widths.
struct DocumentSaveIndicator: View {
    let session: EditorSession
    let height: CGFloat
    @State private var showingStatus = false

    var body: some View {
        Button { showingStatus.toggle() } label: {
            AuraDot(color: session.hasPendingSave || !session.ready ? .orange : .blue, diameter: 7)
                .frame(width: 44, height: height)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Save status for \(session.notebook.title)")
        .accessibilityValue(session.status)
        .accessibilityHint("Shows the current document's save status.")
        .accessibilityIdentifier("workspace.saveStatus")
        .help(session.status)
        .popover(isPresented: $showingStatus, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.status).font(.subheadline.weight(.semibold))
                Text(session.notebook.title).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(idealWidth: 240, maxWidth: 300, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}
