import PencilKit

extension EditorSession {
    func applySmartShape(_ match: SmartShapeMatch, before: PKDrawing, snapshot: PKDrawing, pageID: UUID, style: InkStyle) async -> Bool {
        guard ready, !busy, page?.id == pageID, let page, let canvas, canvas.drawing == snapshot,
              snapshot.strokes.count == before.strokes.count + 1,
              CGRect(origin: .zero, size: page.logicalSize).insetBy(dx: -2, dy: -2).contains(match.rect) else { return false }
        let source = PKDrawing(strokes: Array(snapshot.strokes.suffix(1)))
        let valid = await Task.detached(priority: .userInitiated) {
            StrokeContent.matches(Array(snapshot.strokes.dropLast()), before.strokes)
        }.value
        guard valid else { return false }
        var item = PageElement(kind: match.kind, rect: match.rect)
        item.reversed = match.reversed; item.red = style.red; item.green = style.green; item.blue = style.blue
        item.lineWidth = style.width; item.opacity = style.opacity
        let data = await Task.detached(priority: .utility) { source.dataRepresentation() }.value
        guard data.count <= 8_388_608, !Task.isCancelled else { return false }
        item.originalInk = data
        do {
            try await storage.write(data, to: "Notebooks/\(notebook.id)/Handwriting/\(item.id).drawing")
            guard ready, !busy, self.page?.id == pageID, self.canvas === canvas, canvas.drawing == snapshot, !Task.isCancelled else { return false }
            return replaceHandwritingContent(before, items: elements + [item], action: "Snap Shape")
        } catch { errorMessage = "The shape could not be saved. Original handwriting was kept. \(error.localizedDescription)"; return false }
    }
}
