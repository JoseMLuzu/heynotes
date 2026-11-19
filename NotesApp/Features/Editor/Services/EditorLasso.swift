import PencilKit

extension EditorSession {
    @discardableResult func applyLasso(_ selection: PageLassoSelection, drawing replacement: PKDrawing,
                                       elements replacementElements: [PageElement], pageID: UUID, action: String) -> Bool {
        guard ready, !busy, !exporting, writingRegion == nil, page?.id == pageID,
              let canvas, (canvas as? InkCanvas)?.pageID == pageID,
              canvas.drawing == selection.drawing, elements == selection.elements,
              canvas.drawingGestureRecognizer.state != .began, canvas.drawingGestureRecognizer.state != .changed else { return false }
        return replaceHandwritingContent(replacement, items: replacementElements, action: action)
    }
}
