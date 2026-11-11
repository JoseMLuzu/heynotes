import SwiftUI

struct NotebookCard: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            NotebookCover(title: notebook.title, color: notebook.coverColor,
                          style: notebook.coverStyle,
                          isPDF: notebook.pages.contains { $0.pdfFilePath != nil }, favorite: notebook.isFavorite)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: NotebookCoverFrames.self,
                                               value: [notebook.id: geometry.frame(in: .global)])
                    }
                }
            LibraryItemCaption(title: notebook.title,
                               detail: "\(notebook.pages.count) \(notebook.pages.count == 1 ? "page" : "pages") · \(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(notebook.title), \(notebook.pages.count) pages\(notebook.isFavorite ? ", favorite" : "")")
        .accessibilityValue("Modified \(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))")
    }
}

/// Equal caption space keeps the cover tops aligned even with wrapped titles.
struct LibraryItemCaption: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.body, weight: .semibold))
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
