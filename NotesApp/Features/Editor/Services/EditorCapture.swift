import Foundation

extension EditorSession {
    func capturePage(expectedPageID: UUID) async -> CapturedPage? {
        guard ready, !busy, !exporting, let page, page.id == expectedPageID else { return nil }
        busy = true; exporting = true
        defer { busy = false; exporting = false }
        guard await flush() else { return nil }
        let descriptor = ExportPage(size: page.logicalSize, template: page.paperTemplate, drawingPath: page.drawingFilePath,
                                   pdfPath: page.pdfFilePath, pdfIndex: page.pdfPageIndex, pdfContentSize: page.contentSize,
                                   elements: elements, includeStudyTape: true)
        do {
            let captured = try await PageCaptureService.shared.capture(descriptor,
                source: StudySource(notebookID: notebook.id, pageID: page.id), title: notebook.title, storage: storage)
            guard self.page?.id == expectedPageID, !Task.isCancelled else { return nil }
            return captured
        } catch { errorMessage = "The region could not be captured. Your notes are preserved. \(error.localizedDescription)"; return nil }
    }
    func highlightPDF(_ region: CGRect, expectedPageID: UUID) async {
        guard ready, !busy, let page, page.id == expectedPageID, let path = page.pdfFilePath, let index = page.pdfPageIndex else {
            errorMessage = "Choose a PDF page with selectable text to use this tool."; return
        }
        busy = true
        do {
            let selected = try await PDFDocumentService.shared.selectText(path: path, index: index, region: region, storage: storage)
            guard self.page?.id == expectedPageID, !Task.isCancelled else { busy = false; return }
            let highlights = selected.lines.map { rect in
                var item = PageElement(kind: .rectangle, rect: rect)
                item.filled = true; item.red = 1; item.green = 0.82; item.blue = 0.15; item.opacity = 0.32
                return item
            }
            busy = false; _ = replaceElements(elements + highlights, action: "Highlight PDF Text")
        } catch { busy = false; errorMessage = error.localizedDescription }
    }
}
