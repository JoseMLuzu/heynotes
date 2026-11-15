import PDFKit

struct PDFTextRegion: Sendable {
    let text: String
    let lines: [CGRect]
}

extension PDFDocumentService {
    func selectText(path: String, index: Int, region: CGRect, storage: DrawingStorage) async throws -> PDFTextRegion {
        let url = try await storage.fileURL(for: path)
        let document = try PDFRendering.open(url)
        guard let page = document.page(at: index), let ref = page.pageRef else { throw DocumentError.invalidPage }
        let size = try PDFRendering.size(of: page)
        let transform = ref.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        let clipped = region.intersection(CGRect(origin: .zero, size: size))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0,
              let selection = page.selection(for: clipped.applying(transform.inverted())),
              let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PDFTextError.noText }
        let lines = selection.selectionsByLine().prefix(500).map { $0.bounds(for: page).applying(transform).intersection(CGRect(origin: .zero, size: size)) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        guard !lines.isEmpty else { throw PDFTextError.noText }
        return PDFTextRegion(text: text, lines: lines)
    }
}

enum PDFTextError: LocalizedError {
    case noText
    var errorDescription: String? { "No selectable PDF text was found in this region. Scanned pages need a text layer. Your original PDF is unchanged." }
}
