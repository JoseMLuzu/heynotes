import SwiftUI

struct NotebookCard: View {
    let notebook: Notebook
    var storage: DrawingStorage = .shared

    var body: some View {
        let notebookID = notebook.id
        let pdfPage = notebook.pages.lazy.filter { $0.pdfFilePath != nil }.min {
            $0.pageIndex == $1.pageIndex ? $0.id.uuidString < $1.id.uuidString : $0.pageIndex < $1.pageIndex
        }
        VStack(alignment: .leading, spacing: 13) {
            Group {
                if let pdfPage, let path = pdfPage.pdfFilePath {
                    PDFDocumentCover(path: path, pageIndex: pdfPage.pdfPageIndex,
                                     favorite: notebook.isFavorite, storage: storage)
                } else {
                    NotebookCover(title: notebook.title, color: notebook.coverColor,
                                  style: notebook.coverStyle, favorite: notebook.isFavorite)
                }
            }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: NotebookCoverFrames.self,
                                               value: [notebookID: geometry.frame(in: .global)])
                    }
                }
            LibraryItemCaption(title: notebook.title,
                               detail: "\(notebook.pages.count) \(notebook.pages.count == 1 ? "page" : "pages") · \(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(notebook.title)\(pdfPage != nil ? ", PDF" : ""), \(notebook.pages.count) pages\(notebook.isFavorite ? ", favorite" : "")")
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
