import PencilKit

extension EditorSession {
    func beginZoomWriting(_ rect: CGRect) {
        guard ready, !busy, let page else { return }
        let clipped = rect.standardized.intersection(CGRect(origin: .zero, size: page.logicalSize))
        guard !clipped.isNull, clipped.width >= 24, clipped.height >= 24 else { return }
        zoomStartDrawing = drawing; writingRegion = clipped
        handwriting.cancel()
    }

    @discardableResult func closeZoomWriting() async -> Bool {
        guard !auxiliaryInputActive, await flush() else { return false }
        finishZoomHistory()
        writingRegion = nil; zoomCanvas = nil
        return true
    }

    /// The window has native per-stroke undo. Closing it retains a single undoable writing session
    /// on the overview canvas, so its history survives disposal of the secondary native canvas.
    func finishZoomHistory() {
        guard let previous = zoomStartDrawing, let canvas, let pageID = page?.id else { zoomStartDrawing = nil; return }
        zoomStartDrawing = nil
        canvas.drawing = drawing
        guard previous != drawing else { return }
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            guard target.page?.id == pageID else { return }
            _ = target.applyToolDrawing(previous, action: "Zoom Writing")
        }
        canvas.undoManager?.setActionName("Zoom Writing")
    }

    func moveWritingRegion(horizontal: Double, vertical: Double) {
        guard !auxiliaryInputActive, let page, var rect = writingRegion else { return }
        rect.origin.x = min(max(0, rect.minX + rect.width * horizontal), page.logicalSize.width - rect.width)
        rect.origin.y = min(max(0, rect.minY + rect.height * vertical), page.logicalSize.height - rect.height)
        writingRegion = rect
    }
}
