import SwiftUI
import PencilKit

extension EditorSession {
    @discardableResult func replaceElements(_ replacement: [PageElement], action: String = "Edit Content", undo: Bool = true) -> Bool {
        guard ready, !busy, let page else { return false }
        let previous = elements, pageID = page.id
        do {
            let encoded = try PageElementsCodec.encode(replacement)
            page.objectsData = encoded; page.updatedAt = .now; notebook.updatedAt = .now
            try context.save()
            elements = replacement
            if undo {
                canvas?.undoManager?.registerUndo(withTarget: self) { target in
                    guard target.page?.id == pageID else { return }
                    _ = target.replaceElements(previous, action: action)
                }
                canvas?.undoManager?.setActionName(action)
            }
            if !replacement.contains(where: { $0.id == selectedElementID }) { selectedElementID = nil }
            return true
        } catch { context.rollback(); errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func insertElement(_ item: PageElement) -> Bool {
        guard replaceElements(elements + [item], action: "Insert \(item.kind.title)") else { return false }
        selectedElementID = item.id; return true
    }
    @discardableResult func updateElement(_ item: PageElement) -> Bool {
        guard let index = elements.firstIndex(where: { $0.id == item.id }) else { return false }
        var copy = elements; copy[index] = item; return replaceElements(copy)
    }
    var selectedElement: PageElement? { elements.first { $0.id == selectedElementID } }
    @discardableResult func duplicateElement(_ id: UUID) -> Bool {
        guard ready, !busy, let page, let original = elements.first(where: { $0.id == id }) else { return false }
        var copy = original; copy.id = UUID()
        copy.x = min(max(0, original.x + 24), max(0, page.logicalSize.width - copy.width))
        copy.y = min(max(0, original.y + 24), max(0, page.logicalSize.height - copy.height))
        // Images are immutable; copies on the same page share bytes and edit independent metadata.
        guard replaceElements(elements + [copy], action: "Duplicate Object") else { return false }
        selectedElementID = copy.id; return true
    }
    @discardableResult func deleteElement(_ id: UUID) -> Bool {
        guard elements.contains(where: { $0.id == id }) else { return false }
        return replaceElements(elements.filter { $0.id != id }, action: "Delete Object")
    }
    func toggleTape(_ id: UUID) {
        if revealedTapes.contains(id) { revealedTapes.remove(id) } else { revealedTapes.insert(id) }
    }
    func addImage(_ data: Data) async -> Bool {
        guard ready, !busy, let page else { return false }
        busy = true
        do {
            let (path, size) = try await PageImageService.importImage(data, notebookID: notebook.id, storage: storage)
            let width = max(1, min(320, page.logicalSize.width * 0.8))
            let height = max(1, min(page.logicalSize.height * 0.8, width * size.height / size.width))
            var item = PageElement(kind: .image, rect: CGRect(x: page.logicalSize.width * 0.1, y: page.logicalSize.height * 0.1, width: width, height: height))
            item.imagePath = path
            let loaded = try await PageImageService.load([item], storage: storage)
            objectImages.merge(loaded) { _, new in new }
            busy = false; return insertElement(item)
        } catch { busy = false; errorMessage = error.localizedDescription; return false }
    }
    func setMargin(_ width: Double) -> Bool {
        guard ready, !busy, let page, page.pdfFilePath != nil, width.isFinite,
              width >= 0, page.contentSize.width + width <= 14400 else { return false }
        let right = page.contentSize.width + width
        let nativeBounds = canvas?.drawing.bounds ?? drawing.bounds
        guard (nativeBounds.isNull || nativeBounds.maxX <= right), elements.allSatisfy({ $0.rect.maxX <= right }) else {
            errorMessage = "Move content inside the new page edge before reducing the note margin. Your notes are preserved."; return false
        }
        page.pdfRightMargin = width; return saveMetadata()
    }
    func bookmark(_ page: NotePage, title: String?) -> Bool {
        guard !busy, page.notebook?.id == notebook.id else { return false }
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        page.bookmarkTitle = value?.isEmpty == false ? String(value!.prefix(80)) : nil
        return saveMetadata()
    }
    func createSection(_ title: String) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !name.isEmpty else { return false }
        let section = NotebookSection(title: String(name.prefix(80)), sortIndex: notebook.sections.count)
        context.insert(section); notebook.sections.append(section); return saveMetadata()
    }
    func renameSection(_ section: NotebookSection, title: String) -> Bool {
        guard !busy, section.notebook?.id == notebook.id, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        section.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); return saveMetadata()
    }
    func moveSection(_ section: NotebookSection, offset: Int) {
        guard !busy else { return }
        var ordered = notebook.orderedSections
        guard let index = ordered.firstIndex(where: { $0.id == section.id }), ordered.indices.contains(index + offset) else { return }
        ordered.swapAt(index, index + offset)
        for (i, value) in ordered.enumerated() { value.sortIndex = i }
        NotebookOrganization.normalize(notebook); _ = saveMetadata()
    }
    func deleteSection(_ section: NotebookSection) {
        guard !busy, section.notebook?.id == notebook.id else { return }
        for page in section.pages { page.section = nil }
        notebook.sections.removeAll { $0.id == section.id }; context.delete(section)
        NotebookOrganization.normalize(notebook); _ = saveMetadata()
    }
    func assign(_ page: NotePage, to section: NotebookSection?) {
        guard !busy, NotebookOrganization.assign(page, to: section, in: notebook) else { return }
        _ = saveMetadata()
    }
    @discardableResult private func saveMetadata() -> Bool {
        do { notebook.updatedAt = .now; try context.save(); return true }
        catch { context.rollback(); errorMessage = error.localizedDescription; return false }
    }
}
