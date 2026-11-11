import PDFKit
import UIKit

/// One top-left coordinate system for PDF preview, ink and export, including crop/rotation.
enum PDFRendering {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw DocumentError.unreadable }
        guard !document.isLocked, document.allowsPrinting else { throw DocumentError.protectedDocument }
        guard document.pageCount > 0 else { throw DocumentError.unreadable }
        return document
    }

    static func size(of page: PDFPage) throws -> CGSize {
        guard let ref = page.pageRef else { throw DocumentError.invalidPage }
        let box = ref.getBoxRect(.cropBox)
        let rotated = abs(ref.rotationAngle % 180) == 90
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1, size.width <= 14400, size.height <= 14400 else { throw DocumentError.invalidPage }
        return size
    }

    static func draw(_ page: PDFPage, size: CGSize, in context: CGContext) {
        UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
        guard let ref = page.pageRef else { return }
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        for annotation in page.annotations where annotation.shouldDisplay {
            annotation.draw(with: .cropBox, in: context)
        }
        context.restoreGState()
    }

    static func paper(_ template: PaperTemplate, size: CGSize, in context: CGContext) {
        TemplateRenderer.draw(template, size: size, in: context)
    }
}
