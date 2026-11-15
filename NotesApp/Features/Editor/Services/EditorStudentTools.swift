import PencilKit

struct ToolRegionRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let rect: CGRect
    let tool: EditorTool
}

extension EditorSession {
    @discardableResult func applyToolDrawing(_ replacement: PKDrawing, action: String) -> Bool {
        guard ready, !busy, let canvas, let pageID = page?.id, (canvas as? InkCanvas)?.pageID == pageID else { return false }
        let previous = canvas.drawing
        guard replacement != previous else { return true }
        handwriting.cancel(); canvas.drawing = replacement
        if let zoomCanvas, zoomCanvas.drawing != replacement { zoomCanvas.drawing = replacement }
        changed(replacement)
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            guard target.page?.id == pageID else { return }; _ = target.applyToolDrawing(previous, action: action)
        }
        canvas.undoManager?.setActionName(action)
        return true
    }

    func eraseHighlighter(along points: [CGPoint], radius: CGFloat) async {
        guard ready, !busy, let pageID = page?.id, let canvas else { return }
        let snapshot = canvas.drawing
        busy = true
        let replacement = await Task.detached(priority: .userInitiated) {
            SelectiveInkEraser.eraseHighlighter(snapshot, along: points, radius: radius)
        }.value
        busy = false
        guard page?.id == pageID, self.canvas === canvas, canvas.drawing == snapshot else { return }
        _ = applyToolDrawing(replacement, action: "Erase Highlighter")
    }

    func insertStamp(at point: CGPoint, symbol: StampSymbol, style: InkStyle) {
        guard let page else { return }
        let side = min(64, page.logicalSize.width, page.logicalSize.height)
        var item = PageElement(kind: .text, rect: CGRect(x: min(max(0, point.x - side / 2), page.logicalSize.width - side),
            y: min(max(0, point.y - side / 2), page.logicalSize.height - side), width: side, height: side))
        item.text = symbol.rawValue; item.fontSize = 48
        item.red = style.red; item.green = style.green; item.blue = style.blue; item.opacity = style.opacity
        _ = insertElement(item)
    }
    func requestSticky(at point: CGPoint, style: StickyNoteStyle) {
        guard ready, !busy, let page else { return }
        let size = CGSize(width: min(240, page.logicalSize.width), height: min(180, page.logicalSize.height))
        var item = PageElement(kind: .text, rect: CGRect(x: min(max(0, point.x), page.logicalSize.width - size.width),
            y: min(max(0, point.y), page.logicalSize.height - size.height), width: size.width, height: size.height))
        item.text = ""; item.fontSize = 20; item.stickyStyle = style; item.folded = false
        item.red = 0.12; item.green = 0.13; item.blue = 0.16
        requestedNote = item
    }
    func toggleSticky(_ id: UUID) {
        guard var item = elements.first(where: { $0.id == id && $0.stickyStyle != nil }) else { return }
        item.folded = !(item.folded ?? false); _ = updateElement(item)
    }
    func requestRegion(_ rect: CGRect, tool: EditorTool) {
        guard ready, !busy, let page else { return }
        let rect = rect.standardized.intersection(CGRect(origin: .zero, size: page.logicalSize))
        guard !rect.isNull, rect.width >= 12, rect.height >= 12 else { return }
        regionRequest = ToolRegionRequest(pageID: page.id, rect: rect, tool: tool)
    }
}
