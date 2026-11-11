import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class LibraryViewModel {
    public private(set) var notebooks: [Notebook] = []
    public private(set) var folders: [Folder] = []
    public private(set) var trashedNotebooks: [Notebook] = []
    public private(set) var trashedFolders: [Folder] = []
    public private(set) var isWorking = false
    public var errorMessage: String?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored let storage: DrawingStorage

    public var modelContext: ModelContext { context }

    public init(context: ModelContext, storage: DrawingStorage = .shared) {
        self.storage = storage
        self.context = context
        reload()
    }

    public func reload() {
        do {
            let allNotebooks = try context.fetch(FetchDescriptor<Notebook>(sortBy: [SortDescriptor(\Notebook.updatedAt, order: .reverse)]))
            let allFolders = try context.fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\Folder.title)]))
            notebooks = allNotebooks.filter { !$0.isInTrash }
            folders = allFolders.filter { !$0.isInTrash }
            trashedNotebooks = allNotebooks.filter { $0.trashedAt != nil && $0.folder?.isInTrash != true }
            trashedFolders = allFolders.filter { $0.trashedAt != nil && $0.parent?.isInTrash != true }
        } catch { errorMessage = "Your library could not be loaded. Your saved data has not been removed. \(error.localizedDescription)" }
    }

    @discardableResult
    public func createNotebook(title: String, color: CoverColor, template: PaperTemplate, folder: Folder?, cover: CoverStyle? = nil) -> Bool {
        perform {
            guard folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            let notebook = Notebook(title: try validated(title), coverColor: color, folder: folder)
            if let cover { notebook.coverStyle = cover }
            context.insert(notebook)
            let page = NotePage(pageIndex: 0, paperTemplate: template)
            context.insert(page)
            notebook.pages.append(page)
        }
    }

    public func createFolder(title: String, parent: Folder? = nil) -> Bool {
        perform {
            guard parent?.isInTrash != true else { throw LibraryError.trashedDestination }
            context.insert(Folder(title: try validated(title), parent: parent))
        }
    }

    public func rename(_ notebook: Notebook, title: String) -> Bool {
        perform { notebook.title = try validated(title); notebook.updatedAt = .now }
    }

    public func rename(_ folder: Folder, title: String) -> Bool {
        perform { folder.title = try validated(title) }
    }

    @discardableResult
    public func changeCover(_ notebook: Notebook, to cover: CoverStyle) -> Bool {
        guard !notebook.isInTrash else { return false }
        guard notebook.coverColorRawValue != cover.rawValue else { return true }
        return perform { notebook.coverStyle = cover; notebook.updatedAt = .now }
    }

    @discardableResult public func changeColor(_ folder: Folder, to color: FolderColor) -> Bool {
        guard !folder.isInTrash else { return false }
        guard folder.color != color else { return true }
        return perform { folder.color = color }
    }

    public func toggleFavorite(_ notebook: Notebook) {
        perform { notebook.isFavorite.toggle() }
    }

    public func move(_ notebook: Notebook, to folder: Folder?) {
        perform {
            guard !notebook.isInTrash, folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            notebook.folder = folder; notebook.updatedAt = .now
        }
    }

    public func duplicate(_ original: Notebook) async {
        guard !isWorking, !original.isInTrash else { return }
        isWorking = true
        defer { isWorking = false }
        let newID = UUID()
        let title = original.title + " Copy"
        let color = original.coverColor
        let coverIdentifier = original.coverColorRawValue
        let folder = original.folder
        var copied: [NotePage] = []
        var pdfCopies: [String: String] = [:]
        var imageCopies: [String: String] = [:]
        var sectionCopies: [UUID: NotebookSection] = [:]
        for section in original.orderedSections { sectionCopies[section.id] = NotebookSection(title: section.title, sortIndex: section.sortIndex) }
        do {
            for source in original.orderedPages {
                let page = NotePage(pageIndex: copied.count, paperTemplate: source.paperTemplate)
                page.pageWidth = source.pageWidth; page.pageHeight = source.pageHeight
                page.pdfPageIndex = source.pdfPageIndex
                page.pdfRightMargin = source.pdfRightMargin; page.bookmarkTitle = source.bookmarkTitle
                page.section = source.section.flatMap { sectionCopies[$0.id] }
                var objects = try PageElementsCodec.decode(source.objectsData)
                for index in objects.indices {
                    objects[index].id = UUID()
                    if let originalPath = objects[index].imagePath {
                        if let copiedPath = imageCopies[originalPath] { objects[index].imagePath = copiedPath }
                        else {
                            let path = "Notebooks/\(newID.uuidString)/Images/\(UUID().uuidString).jpg"
                            try await storage.copyFile(from: storage.fileURL(for: originalPath), to: path)
                            imageCopies[originalPath] = path; objects[index].imagePath = path
                        }
                    }
                }
                page.objectsData = try PageElementsCodec.encode(objects)
                if let sourcePDF = source.pdfFilePath {
                    if let existing = pdfCopies[sourcePDF] { page.pdfFilePath = existing }
                    else {
                        let path = "Notebooks/\(newID.uuidString)/Sources/\(UUID().uuidString).pdf"
                        let sourceURL = try await storage.fileURL(for: sourcePDF)
                        try await storage.copyFile(from: sourceURL, to: path)
                        pdfCopies[sourcePDF] = path; page.pdfFilePath = path
                    }
                }
                let sourcePath = source.drawingFilePath ?? DrawingStorage.path(notebook: original.id, page: source.id)
                if try await storage.exists(sourcePath) {
                    let data = try await storage.read(sourcePath)
                    let path = DrawingStorage.path(notebook: newID, page: page.id)
                    try await storage.write(data, to: path)
                    page.drawingFilePath = path
                } else if source.drawingFilePath != nil { throw CocoaError(.fileNoSuchFile) }
                copied.append(page)
            }
            guard !original.isInTrash, folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            perform {
                let copy = Notebook(title: title, coverColor: color, folder: folder, id: newID)
                copy.coverColorRawValue = coverIdentifier
                context.insert(copy)
                for section in sectionCopies.values { context.insert(section); copy.sections.append(section) }
                for page in copied { context.insert(page); copy.pages.append(page) }
            }
        } catch { errorMessage = "The notebook could not be copied. Its source files are unchanged. \(error.localizedDescription)" }
    }

    /// Soft deletion retains metadata, relationships, permanent IDs and every binary file.
    public func delete(_ notebook: Notebook) { perform { notebook.trashedAt = .now } }
    public func delete(_ folder: Folder) { perform { folder.trashedAt = .now } }

    public func restore(_ notebook: Notebook) {
        perform {
            guard notebook.folder?.isInTrash != true else { throw LibraryError.trashedDestination }
            notebook.trashedAt = nil
        }
    }
    public func restore(_ folder: Folder) {
        perform {
            guard folder.parent?.isInTrash != true else { throw LibraryError.trashedDestination }
            folder.trashedAt = nil
        }
    }
    public func toggleFavorite(_ folder: Folder) { perform { folder.isFavorite.toggle() } }

    @discardableResult
    public func move(_ folder: Folder, to parent: Folder?) -> Bool {
        perform {
            guard !folder.isInTrash, parent?.isInTrash != true else { throw LibraryError.trashedDestination }
            var ancestor = parent
            var visited = Set<UUID>()
            while let candidate = ancestor {
                guard candidate.id != folder.id, visited.insert(candidate.id).inserted else { throw LibraryError.folderCycle }
                ancestor = candidate.parent
            }
            folder.parent = parent
        }
    }

    public func documents(inSubtreeOf folder: Folder) -> [Notebook] {
        let ids = folder.subtreeIDs
        return notebooks.filter { $0.folder.map { ids.contains($0.id) } == true }
    }

    public func validParents(for folder: Folder) -> [Folder] {
        let excluded = folder.subtreeIDs
        return folders.filter { !excluded.contains($0.id) }.sorted { $0.pathTitle.localizedStandardCompare($1.pathTitle) == .orderedAscending }
    }

    @discardableResult
    private func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            try context.save()
            reload()
            return true
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
            reload()
            return false
        }
    }

    private func validated(_ title: String) throws -> String {
        let result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LibraryError.emptyTitle }
        return result
    }
}

enum LibraryError: LocalizedError {
    case emptyTitle, folderCycle, trashedDestination
    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a title before saving."
        case .folderCycle: "A folder cannot be moved inside itself or one of its subfolders."
        case .trashedDestination: "Restore the containing folder from Trash before using this location."
        }
    }
}
