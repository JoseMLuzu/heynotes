import Foundation

@MainActor public enum NotebookOrganization {
    public static func assign(_ page: NotePage, to section: NotebookSection?, in notebook: Notebook) -> Bool {
        guard page.notebook?.id == notebook.id, section == nil || section?.notebook?.id == notebook.id else { return false }
        page.section = section
        page.pageIndex = (notebook.pages.map(\.pageIndex).max() ?? 0) + 1
        normalize(notebook); return true
    }
    public static func normalize(_ notebook: Notebook) {
        let sections = notebook.orderedSections
        for (index, section) in sections.enumerated() { section.sortIndex = index }
        let ranks = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($0.element.id, $0.offset) })
        let pages = notebook.orderedPages.sorted {
            let a = $0.section.flatMap { ranks[$0.id] } ?? sections.count
            let b = $1.section.flatMap { ranks[$0.id] } ?? sections.count
            return a == b ? $0.pageIndex < $1.pageIndex : a < b
        }
        PageOrdering.normalize(pages)
    }
}
