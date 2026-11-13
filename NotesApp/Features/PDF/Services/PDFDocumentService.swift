import Foundation
import PDFKit
import UIKit

struct ImportedPDF: Sendable {
    let path: String
    let pageSizes: [CGSize]
}

enum DocumentError: LocalizedError {
    case unreadable, protectedDocument, invalidPage, emptyExport
    var errorDescription: String? {
        switch self {
        case .unreadable: "This PDF could not be read. The source file has not been changed."
        case .protectedDocument: "This PDF is locked or restricts printing. Import an unlocked, printable copy."
        case .invalidPage: "A PDF page is missing or has unsupported dimensions."
        case .emptyExport: "There are no pages to export."
        }
    }
}

/// PDFKit objects stay confined to the worker actor; only immutable values/images leave it.
actor PDFDocumentService {
    static let shared = PDFDocumentService()
    // Gallery work cannot sit in front of a full-size page render on the same actor.
    static let thumbnails = PDFDocumentService(imageByteLimit: 4 * 1024 * 1024, documentLimit: 1)
    static let importPreviews = PDFDocumentService(imageByteLimit: 4 * 1024 * 1024, documentLimit: 1)

    private struct ImageKey: Hashable {
        let source: FileFingerprint
        let index: Int
        let maxPixels: Double
    }
    private var images: CostLimitedCache<ImageKey, UIImage>
    private var documents: CostLimitedCache<FileFingerprint, PDFDocument>
    private var renders = 0
    private var opens = 0

    init(imageByteLimit: Int = 24 * 1024 * 1024, documentLimit: Int = 2) {
        images = CostLimitedCache(costLimit: max(0, imageByteLimit), countLimit: 128)
        documents = CostLimitedCache(costLimit: max(0, documentLimit), countLimit: max(0, documentLimit))
    }

    struct CacheStatistics: Sendable {
        let renders: Int
        let documentOpens: Int
        let imageBytes: Int
        let imageCount: Int
    }
    func cacheStatistics() -> CacheStatistics {
        CacheStatistics(renders: renders, documentOpens: opens, imageBytes: images.totalCost, imageCount: images.count)
    }
    func clearCaches() { images.removeAll(); documents.removeAll() }

    func importDocument(from source: URL, notebookID: UUID, storage: DrawingStorage = .shared) async throws -> ImportedPDF {
        let path = "Notebooks/\(notebookID.uuidString)/Sources/\(UUID().uuidString).pdf"
        try await storage.copyFile(from: source, to: path)
        let url = try await storage.fileURL(for: path)
        // Validation follows the private copy: file-provider URLs may expire after the picker closes.
        let document = try PDFRendering.open(url)
        var sizes: [CGSize] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { throw DocumentError.invalidPage }
            sizes.append(try PDFRendering.size(of: page))
        }
        return ImportedPDF(path: path, pageSizes: sizes)
    }

    func background(path: String, index: Int, storage: DrawingStorage = .shared, maxPixels: CGFloat = 2400) async throws -> UIImage {
        try Task.checkCancellation()
        guard maxPixels.isFinite, maxPixels >= 1 else { throw DocumentError.invalidPage }
        let pixels = min(2400, maxPixels)
        let url = try await storage.fileURL(for: path)
        let fingerprint = try FileFingerprint(url: url)
        let key = ImageKey(source: fingerprint, index: index, maxPixels: pixels)
        if let cached = images.value(for: key) { return cached }
        try Task.checkCancellation()
        let document: PDFDocument
        if let cached = documents.value(for: fingerprint) { document = cached }
        else {
            document = try PDFRendering.open(url)
            opens += 1
            documents.insert(document, for: fingerprint, cost: 1)
        }
        guard let page = document.page(at: index) else { throw DocumentError.invalidPage }
        let size = try PDFRendering.size(of: page)
        let scale = min(2, pixels / max(size.width, size.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale; format.opaque = true
        let image = autoreleasepool {
            UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                PDFRendering.draw(page, size: size, in: renderer.cgContext)
            }
        }
        renders += 1
        try Task.checkCancellation()
        if let cg = image.cgImage { images.insert(image, for: key, cost: cg.bytesPerRow * cg.height) }
        return image
    }
}
