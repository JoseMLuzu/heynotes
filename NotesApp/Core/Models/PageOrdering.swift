import Foundation

@MainActor
public enum PageOrdering {
    public static func normalize(_ pages: [NotePage]) {
        for (index, page) in pages.enumerated() { page.pageIndex = index }
    }

    public static func move(_ page: NotePage, in notebook: Notebook, offset: Int) {
        var pages = notebook.orderedPages
        guard let from = pages.firstIndex(where: { $0.id == page.id }) else { return }
        let to = min(max(0, from + offset), pages.count - 1)
        pages.insert(pages.remove(at: from), at: to)
        normalize(pages)
    }
}
