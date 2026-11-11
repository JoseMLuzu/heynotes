import SwiftUI
import SwiftData
import PencilKit

@MainActor @Observable
final class EditorSession {
    let notebook: Notebook
    let context: ModelContext
    let storage: DrawingStorage
    let handwriting: HandwritingAssistant
    var page: NotePage?
    @ObservationIgnored var drawing = PKDrawing()
    @ObservationIgnored var pdfBackground: UIImage?
    var elements: [PageElement] = []
    var selectedElementID: UUID?
    var revealedTapes: Set<UUID> = []
    @ObservationIgnored var objectImages: [String: UIImage] = [:]
    var pageTurnDirection = 1
    var ready = false
    var busy = false
    var exporting = false
    var errorMessage: String?
    var status = "Loading…"
    private(set) var hasPendingSave = false
    @ObservationIgnored var canvas: PKCanvasView?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var savedRevision = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Bool, Never>?

    init(notebook: Notebook, context: ModelContext, storage: DrawingStorage = .shared, handwriting: HandwritingAssistant? = nil) {
        self.notebook = notebook; self.context = context; self.storage = storage
        self.handwriting = handwriting ?? HandwritingAssistant()
    }

    var path: String? {
        guard let page else { return nil }
        return page.drawingFilePath ?? DrawingStorage.path(notebook: notebook.id, page: page.id)
    }

    func open(_ target: NotePage) async {
        guard !busy else { return }
        handwriting.cancel()
        busy = true
        defer { busy = false }
        let previousIndex = page?.pageIndex
        let previousID = page?.id
        let request = PageLoadRequest(drawingPath: target.drawingFilePath,
                                      fallbackDrawingPath: DrawingStorage.path(notebook: notebook.id, page: target.id),
                                      pdfPath: target.pdfFilePath, pdfIndex: target.pdfPageIndex)
        // A different page can load while outgoing ink saves. Never race a same-file reload.
        let canOverlap = target.id != previousID && request.resolvedDrawingPath != path
        let loading: Task<LoadedNotePage, Error>? = canOverlap ? Task { [storage] in
            try await PageLoader.load(request, storage: storage)
        } : nil
        guard await flush() else { loading?.cancel(); return }
        do {
            let content = try await PageLoader.elements(target.objectsData)
            let images = try await PageImageService.load(content, storage: storage)
            let loaded: LoadedNotePage
            if let loading { loaded = try await loading.value }
            else { loaded = try await PageLoader.load(request, storage: storage) }
            // Keep the old canvas visible until the destination has loaded completely.
            pageTurnDirection = target.pageIndex >= (previousIndex ?? 0) ? 1 : -1
            page = target; drawing = loaded.drawing; pdfBackground = loaded.background
            elements = content; objectImages = images; revealedTapes = []; selectedElementID = nil
            handwriting.reset(to: loaded.drawing)
            revision = 0; savedRevision = 0; hasPendingSave = false
            if previousID != target.id { canvas = nil }
            ready = true; status = "Saved on iPad"
        } catch { loading?.cancel(); page = target; ready = false; canvas = nil; status = "Page unavailable"; errorMessage = "The page could not be opened. Its files have been preserved. \(error.localizedDescription)" }
    }

    func changed(_ value: PKDrawing) {
        guard ready else { return }
        drawing = value; revision += 1
        handwriting.changed(value, session: self)
        if !hasPendingSave { hasPendingSave = true }
        if status != "Unsaved changes" { status = "Unsaved changes" }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            _ = await self?.saveCheckpoint()
        }
    }

    /// Explicit navigation/background/export flushes drain all revisions. Debounce saves only one.
    func flush() async -> Bool {
        // Capture the native canvas before navigation even if its final delegate callback is queued.
        if let canvas, (canvas as? InkCanvas)?.pageID == page?.id, canvas.drawing != drawing {
            changed(canvas.drawing)
        }
        repeat {
            guard await saveCheckpoint() else { return false }
        } while ready && revision != savedRevision
        return true
    }

    private func saveCheckpoint() async -> Bool {
        if let saving { return await saving.value }
        guard ready, revision != savedRevision, let page, let path else { return true }
        let snapshot = drawing
        let version = revision
        let task = Task { [self] in
            defer { saving = nil }
            do {
                status = "Saving…"
                let data = await Task.detached(priority: .utility) { snapshot.dataRepresentation() }.value
                try await storage.write(data, to: path)
                page.drawingFilePath = path
                page.updatedAt = .now; notebook.updatedAt = .now
                try context.save()
                savedRevision = version
                hasPendingSave = revision != savedRevision
                status = revision == savedRevision ? "Saved on iPad" : "Unsaved changes"
                return true
            } catch {
                status = "Save failed — retry"
                errorMessage = "Your latest drawing is still in memory. Keep this notebook open and retry saving. \(error.localizedDescription)"
                return false
            }
        }
        saving = task
        return await task.value
    }

    func clearHandwriting() {
        guard ready, !busy, let canvas, (canvas as? InkCanvas)?.pageID == page?.id else { return }
        replaceHandwriting(with: PKDrawing(), on: canvas)
    }

    private func replaceHandwriting(with replacement: PKDrawing, on canvas: PKCanvasView) {
        guard ready, !busy, (canvas as? InkCanvas)?.pageID == page?.id else { return }
        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: canvas) { [weak self] target in
            self?.replaceHandwriting(with: previous, on: target)
        }
        canvas.undoManager?.setActionName("Clear Handwriting")
        canvas.drawing = replacement
        changed(replacement)
    }

    func backgroundSave() {
        handwriting.cancel()
        let token = UIApplication.shared.beginBackgroundTask(withName: "Save handwriting")
        Task {
            _ = await flush()
            handwriting.reset(to: canvas?.drawing ?? drawing)
            if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
        }
    }

    func recover() async {
        guard !ready, let path, let page else { return }
        do {
            let objects = try await PageLoader.elements(page.objectsData)
            let images = try await PageImageService.load(objects, storage: storage)
            if let source = page.pdfFilePath {
                guard let index = page.pdfPageIndex else { throw DocumentError.invalidPage }
                pdfBackground = try await PDFDocumentService.shared.background(path: source, index: index, storage: storage)
            }
            let data = try await storage.read(path + ".backup")
            let recovered = try PKDrawing(data: data) // Validate before replacing anything.
            _ = try await storage.restoreBackup(path)
            drawing = recovered; ready = true; hasPendingSave = false; status = "Backup restored"
            elements = objects; objectImages = images; revealedTapes = []; selectedElementID = nil
        } catch { errorMessage = "A valid backup could not be restored. Original files were kept. \(error.localizedDescription)" }
    }

    func turnPage(_ direction: Int, creatingIfNeeded: Bool = false) async {
        guard ready, !busy, direction == 1 || direction == -1 else { return }
        let pages = notebook.orderedPages
        guard let index = pages.firstIndex(where: { $0.id == page?.id }) else { return }
        let next = index + direction
        if pages.indices.contains(next) {
            await open(pages[next])
        } else if direction == 1, creatingIfNeeded {
            await addPage()
        }
    }

    func addPage() async {
        guard !busy else { return }
        busy = true
        guard await flush() else { busy = false; return }
        let new = NotePage(pageIndex: notebook.pages.count, paperTemplate: page?.paperTemplate ?? .blank)
        new.pageWidth = page.map { Double($0.logicalSize.width) }; new.pageHeight = page.map { Double($0.logicalSize.height) }
        new.section = page?.section
        context.insert(new); notebook.pages.append(new)
        NotebookOrganization.normalize(notebook)
        let success = commit()
        busy = false
        if success { await open(new) }
    }

    func duplicatePage() async {
        guard !busy, ready, let source = page else { return }
        busy = true
        guard await flush() else { busy = false; return }
        let new = NotePage(pageIndex: notebook.pages.count, paperTemplate: source.paperTemplate)
        new.pdfFilePath = source.pdfFilePath; new.pdfPageIndex = source.pdfPageIndex
        new.pageWidth = source.pageWidth; new.pageHeight = source.pageHeight
        new.pdfRightMargin = source.pdfRightMargin; new.bookmarkTitle = source.bookmarkTitle; new.section = source.section
        do {
            var objects = try PageElementsCodec.decode(source.objectsData)
            for index in objects.indices { objects[index].id = UUID() }
            new.objectsData = try PageElementsCodec.encode(objects)
            if let sourcePath = source.drawingFilePath {
                let data = try await storage.read(sourcePath)
                _ = try PKDrawing(data: data)
                let destination = DrawingStorage.path(notebook: notebook.id, page: new.id)
                try await storage.write(data, to: destination)
                new.drawingFilePath = destination
            }
            context.insert(new); notebook.pages.append(new)
            NotebookOrganization.normalize(notebook)
            let success = commit()
            busy = false
            if success { await open(new) }
        } catch { busy = false; errorMessage = error.localizedDescription }
    }

    func deletePage() async {
        guard !busy, let page, notebook.pages.count > 1 else { return }
        busy = true
        guard await flush() else { busy = false; return }
        // File bytes and their backup are deliberately retained for recovery.
        notebook.pages.removeAll { $0.id == page.id }
        context.delete(page)
        PageOrdering.normalize(notebook.orderedPages)
        let success = commit()
        busy = false
        guard success else { return }
        if let first = notebook.orderedPages.first { await open(first) }
    }

    func movePage(_ offset: Int) {
        guard let page, !busy else { return }
        let pages = notebook.orderedPages
        if let index = pages.firstIndex(where: { $0.id == page.id }), pages.indices.contains(index + offset) { page.section = pages[index + offset].section }
        PageOrdering.move(page, in: notebook, offset: offset)
        _ = commit()
    }

    func changeTemplate(_ template: PaperTemplate) {
        guard let page, ready, !busy, page.pdfFilePath == nil,
              page.paperTemplateRawValue != template.rawValue else { return }
        page.paperTemplate = template
        _ = commit()
    }

    func export(currentPageOnly: Bool, includeStudyTape: Bool = false) async -> URL? {
        guard !busy, ready else { return nil }
        busy = true; exporting = true
        defer { busy = false; exporting = false }
        guard await flush() else { return nil }
        let pages = currentPageOnly ? page.map { [$0] } ?? [] : notebook.orderedPages
        do {
            var snapshots: [ExportPage] = []
            for page in pages {
                let fallback = DrawingStorage.path(notebook: notebook.id, page: page.id)
                let exists = try await storage.exists(fallback)
                snapshots.append(ExportPage(size: page.logicalSize, template: page.paperTemplate,
                                            drawingPath: page.drawingFilePath ?? (exists ? fallback : nil),
                                            pdfPath: page.pdfFilePath, pdfIndex: page.pdfPageIndex,
                                            pdfContentSize: page.contentSize, elements: try PageElementsCodec.decode(page.objectsData),
                                            includeStudyTape: includeStudyTape))
            }
            return try await PDFExportService.shared.export(pages: snapshots, storage: storage)
        } catch { errorMessage = "The PDF could not be exported. Your notebook is unchanged. \(error.localizedDescription)"; return nil }
    }

    private func commit() -> Bool {
        do { notebook.updatedAt = .now; try context.save(); return true }
        catch { context.rollback(); errorMessage = error.localizedDescription; return false }
    }
}
