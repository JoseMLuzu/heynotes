import Foundation

struct PDFImportDraft: Identifiable, Sendable {
    let id: UUID
    let title: String
    let sourceURL: URL
    let document: ImportedPDF
    let storage: DrawingStorage
    var pageCount: Int { document.pageSizes.count }
}

/// Picker access ends after staging. Only an app-owned temporary copy is used by the selector.
actor PDFImportStaging {
    static let shared = PDFImportStaging()
    private let root: URL
    private var directories: [UUID: URL] = [:]

    init(root: URL = URL.temporaryDirectory.appendingPathComponent("HeyNotesPDFImports", isDirectory: true)) {
        self.root = root
    }

    func prepare(_ source: URL) async throws -> PDFImportDraft {
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let storage = DrawingStorage(root: directory)
        do {
            let imported = try await PDFDocumentService.shared.importDocument(from: source, notebookID: id, storage: storage)
            try Task.checkCancellation()
            let url = try await storage.fileURL(for: imported.path)
            // The directory name is retained in the draft URL, but never trusted for deletion.
            directories[id] = directory
            return PDFImportDraft(id: id, title: source.deletingPathExtension().lastPathComponent,
                                  sourceURL: url, document: imported, storage: storage)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func discard(_ draft: PDFImportDraft) async {
        guard let directory = directories.removeValue(forKey: draft.id) else { return }
        await PDFDocumentService.importPreviews.clearCaches()
        try? FileManager.default.removeItem(at: directory)
    }
}
