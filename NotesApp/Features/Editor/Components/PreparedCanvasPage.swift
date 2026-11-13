import UIKit

/// Main-actor snapshot; never retains a SwiftData page inside a reusable canvas.
struct PreparedCanvasPage {
    let id: UUID
    let size: CGSize
    let contentSize: CGSize
    let template: PaperTemplate
    let content: PreparedPageContent

    @MainActor init(page: NotePage, content: PreparedPageContent) {
        id = page.id; size = page.logicalSize; contentSize = page.contentSize
        template = page.paperTemplate; self.content = content
    }

    @MainActor func makeHost() -> CanvasHost {
        let host = CanvasHost(pageSize: size)
        host.ink.pageID = id; host.ink.drawing = content.drawing
        host.paper.pdfImage = content.background; host.paper.pdfContentSize = contentSize
        host.paper.template = template
        host.objectContent.images = content.images; host.objectContent.elements = content.elements
        host.objectContent.isHidden = !content.elements.contains { $0.kind != .tape }
        host.objectControls.elements = content.elements
        host.objectControls.isHidden = !content.elements.contains { $0.kind == .tape }
        host.isUserInteractionEnabled = false; host.editorAllowsInk = false
        host.accessibilityElementsHidden = true
        return host
    }
}
