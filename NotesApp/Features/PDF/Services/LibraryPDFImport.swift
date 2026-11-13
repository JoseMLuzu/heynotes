import Foundation

extension LibraryViewModel {
    @discardableResult
    func importPDF(from url: URL, folder: Folder?, storage: DrawingStorage? = nil,
                   selectedPageIndices: [Int]? = nil, title: String? = nil) async -> Bool {
        let storage = storage ?? self.storage
        let id = UUID()
        errorMessage = nil
        do {
            guard folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            let imported = try await PDFDocumentService.shared.importDocument(from: url, notebookID: id, storage: storage)
            guard folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            let indices = try PDFPageSelection.validated(selectedPageIndices ?? Array(imported.pageSizes.indices), pageCount: imported.pageSizes.count)
            let name = title ?? url.deletingPathExtension().lastPathComponent
            let notebook = Notebook(title: name.isEmpty ? "Imported PDF" : name, coverColor: .blue, folder: folder, id: id)
            modelContext.insert(notebook)
            for (index, sourceIndex) in indices.enumerated() {
                let size = imported.pageSizes[sourceIndex]
                let page = NotePage(pageIndex: index)
                page.pdfFilePath = imported.path; page.pdfPageIndex = sourceIndex
                page.pageWidth = size.width; page.pageHeight = size.height
                modelContext.insert(page); notebook.pages.append(page)
            }
            try modelContext.save()
            reload()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = "The PDF could not be imported. The source file is unchanged. \(error.localizedDescription)"
            reload()
            return false
        }
    }
}
