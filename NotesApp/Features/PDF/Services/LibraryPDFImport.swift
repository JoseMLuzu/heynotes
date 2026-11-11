import Foundation

extension LibraryViewModel {
    func importPDF(from url: URL, folder: Folder?, storage: DrawingStorage? = nil) async {
        let storage = storage ?? self.storage
        let id = UUID()
        do {
            guard folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            let imported = try await PDFDocumentService.shared.importDocument(from: url, notebookID: id, storage: storage)
            guard folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            let title = url.deletingPathExtension().lastPathComponent
            let notebook = Notebook(title: title.isEmpty ? "Imported PDF" : title, coverColor: .blue, folder: folder, id: id)
            modelContext.insert(notebook)
            for (index, size) in imported.pageSizes.enumerated() {
                let page = NotePage(pageIndex: index)
                page.pdfFilePath = imported.path; page.pdfPageIndex = index
                page.pageWidth = size.width; page.pageHeight = size.height
                modelContext.insert(page); notebook.pages.append(page)
            }
            try modelContext.save()
            reload()
        } catch {
            modelContext.rollback()
            errorMessage = "The PDF could not be imported. The source file is unchanged. \(error.localizedDescription)"
            reload()
        }
    }
}
