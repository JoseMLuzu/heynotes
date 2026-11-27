import Foundation

/// Metadata only. The caller commits these changes with the local journal or rolls back.
@MainActor public enum PageRecovery {
    @discardableResult public static func remove(_ page: NotePage, from notebook: Notebook, at date: Date = .now) -> Bool {
        guard page.trashedAt == nil, notebook.activePageCount > 1,
              page.notebook?.id == notebook.id else { return false }
        page.trashedAt = date
        PageOrdering.normalize(notebook.orderedPages)
        return true
    }

    @discardableResult public static func restore(_ page: NotePage, in notebook: Notebook) -> Bool {
        guard page.trashedAt != nil, page.notebook?.id == notebook.id else { return false }
        var pages = notebook.orderedPages
        let position = min(max(page.pageIndex, 0), pages.count)
        page.trashedAt = nil
        pages.insert(page, at: position)
        PageOrdering.normalize(pages)
        NotebookOrganization.normalize(notebook)
        return true
    }
}
