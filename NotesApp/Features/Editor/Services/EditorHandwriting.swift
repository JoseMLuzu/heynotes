import PencilKit
import UIKit

extension EditorSession {
    /// Only commit if the page and full drawing are still the exact snapshot that was recognized.
    /// Source ink is embedded in the text object and archived before removing any live strokes.
    @discardableResult
    func applyRecognizedHandwriting(_ text: String, source: PKDrawing, snapshot: PKDrawing,
                                    pageID: UUID, fontName: String, fontPath: String? = nil,
                                    recognizedLines: [RecognizedHandwritingLine]? = nil, options: HandwritingLayoutOptions = .init(),
                                    isCurrent: () -> Bool = { true }) async -> Bool {
        guard ready, !busy, page?.id == pageID, let page, let canvas,
              (canvas as? InkCanvas)?.pageID == pageID, canvas.drawing == snapshot,
              canvas.drawingGestureRecognizer.state != .began, canvas.drawingGestureRecognizer.state != .changed,
              !source.strokes.isEmpty, source.strokes.count <= snapshot.strokes.count,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let bounds = source.bounds
        guard !bounds.isNull, bounds.minX >= 0, bounds.minY >= 0 else { return false }
        let isSuffix = await Task.detached(priority: .utility) {
            StrokeContent.matches(Array(snapshot.strokes.suffix(source.strokes.count)), source.strokes)
        }.value
        guard isSuffix, isCurrent() else { return false }
        do {
            if let fontPath {
                let asset = try await HandwritingFontStore.shared.load(path: fontPath, storage: storage)
                guard asset.name == fontName else { return false }
            }
            guard ready, !busy, self.page?.id == pageID, isCurrent(), !Task.isCancelled else { return false }
            let lines = recognizedLines ?? [RecognizedHandwritingLine(text: text, bounds: bounds)]
            guard var conversions = HandwritingTextLayout.make(lines: lines, source: source, pageSize: page.logicalSize,
                template: page.pdfFilePath == nil ? page.paperTemplate : nil, fontName: fontName,
                fontPath: fontPath, options: options) else { return false }
            for index in conversions.indices {
                let ink = conversions[index].ink
                let data = await Task.detached(priority: .utility) { ink.dataRepresentation() }.value
                conversions[index].item.originalInk = data
                // Retained even after deleting a text object/undo, for crash/manual recovery.
                try await storage.write(data, to: "Notebooks/\(notebook.id)/Handwriting/\(conversions[index].item.id).drawing")
            }
            guard ready, !busy, self.page?.id == pageID, canvas.drawing == snapshot,
                  canvas.drawingGestureRecognizer.state != .began, canvas.drawingGestureRecognizer.state != .changed,
                  self.canvas === canvas, !Task.isCancelled else { return false }
            guard isCurrent() else { return false }
            let remaining = PKDrawing(strokes: Array(snapshot.strokes.dropLast(source.strokes.count)))
            return replaceHandwritingContent(remaining, items: elements + conversions.map(\.item), action: "Clean Handwriting")
        } catch { errorMessage = "Handwriting could not be converted. Original ink was kept. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func restoreOriginalInk(_ id: UUID) -> Bool {
        guard ready, !busy, let canvas, let item = elements.first(where: { $0.id == id }),
              let data = item.originalInk else { return false }
        do {
            var original = try PKDrawing(data: data)
            guard !original.strokes.isEmpty else { throw PageElementError.unreadable }
            // Moving the converted text also moves the restored phrase to that position.
            original = original.transformed(using: CGAffineTransform(translationX: item.x - (item.originalInkAnchorX ?? original.bounds.minX),
                                                                    y: item.y - (item.originalInkAnchorY ?? original.bounds.minY)))
            let replacement = PKDrawing(strokes: canvas.drawing.strokes + original.strokes)
            return replaceHandwritingContent(replacement, items: elements.filter { $0.id != id }, action: "Restore Original Ink")
        } catch { errorMessage = "The original handwriting could not be read. Stored data was kept."; return false }
    }

    /// Ink and text use one Undo action. Metadata is saved first; a crash during the ink write
    /// may show duplicate content, but the source archive and embedded strokes prevent loss.
    @discardableResult
    func replaceHandwritingContent(_ replacement: PKDrawing, items: [PageElement], action: String) -> Bool {
        guard ready, !busy, let pageID = page?.id, let canvas,
              (canvas as? InkCanvas)?.pageID == pageID else { return false }
        let oldDrawing = canvas.drawing, oldItems = elements
        guard replaceElements(items, action: action, undo: false) else { return false }
        handwriting.reset(to: replacement)
        canvas.drawing = replacement
        if let zoomCanvas, zoomCanvas.drawing != replacement { zoomCanvas.drawing = replacement }
        changed(replacement)
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            guard target.page?.id == pageID else { return }
            _ = target.replaceHandwritingContent(oldDrawing, items: oldItems, action: action)
        }
        canvas.undoManager?.setActionName(action)
        selectedElementID = nil
        return true
    }
}
