import Foundation
import UIKit
import PencilKit

struct ThumbnailRequest: Sendable {
    let size: CGSize
    let template: PaperTemplate
    let drawingPath: String?
    let fallbackPath: String
    let pdfPath: String?
    let pdfIndex: Int?
    var pdfContentSize: CGSize? = nil
    var elements: [PageElement] = []
    /// Raw SwiftData value is captured by the view; decoding belongs to the worker.
    var objectsData: Data? = nil
}

actor PageThumbnailService {
    static let shared = PageThumbnailService()
    private struct Key: Hashable {
        let ink: FileFingerprint?
        let pdf: FileFingerprint?
        let pdfIndex: Int?
        let width: Double
        let height: Double
        let template: PaperTemplate
        let objects: Data
        let pdfWidth: Double?
        let imageSources: [FileFingerprint]
    }
    private var images = CostLimitedCache<Key, UIImage>(costLimit: 4 * 1024 * 1024, countLimit: 128)
    private var hits = 0, renders = 0, largestKeyBytes = 0
    struct Statistics: Sendable {
        let hits: Int
        let renders: Int
        let cachedImages: Int
        let estimatedBytes: Int
        let largestKeyBytes: Int
    }
    func statistics() -> Statistics {
        Statistics(hits: hits, renders: renders, cachedImages: images.count, estimatedBytes: images.totalCost, largestKeyBytes: largestKeyBytes)
    }
    func clearCache() { images.removeAll() }

    func thumbnail(_ request: ThumbnailRequest, storage: DrawingStorage = .shared) async throws -> UIImage {
        try Task.checkCancellation()
        guard request.size.width.isFinite, request.size.height.isFinite,
              request.size.width > 0, request.size.height > 0 else { throw DocumentError.invalidPage }
        let decoded: [PageElement]
        if let data = request.objectsData { decoded = try await PageLoader.elements(data) }
        else { decoded = request.elements; try PageElementsCodec.validate(decoded) }
        // Recovery archives and their initial anchors do not affect pixels. Never
        // base64-encode or retain megabytes of source ink in an image-cache key.
        let elements = decoded.map { original in
            var item = original
            item.originalInk = nil; item.originalInkAnchorX = nil; item.originalInkAnchorY = nil
            return item
        }
        let inkURL = try await storage.fileURL(for: request.drawingPath ?? request.fallbackPath)
        let ink: FileFingerprint?
        if FileManager.default.fileExists(atPath: inkURL.path) { ink = try FileFingerprint(url: inkURL) }
        else if request.drawingPath != nil { throw CocoaError(.fileNoSuchFile) }
        else { ink = nil }
        let pdf: FileFingerprint?
        if let path = request.pdfPath { pdf = try FileFingerprint(url: await storage.fileURL(for: path)) }
        else { pdf = nil }
        var sources: [FileFingerprint] = []
        for path in Set(elements.flatMap(\.assetPaths)).sorted() {
            sources.append(try FileFingerprint(url: await storage.fileURL(for: path)))
        }
        let key = Key(ink: ink, pdf: pdf, pdfIndex: request.pdfIndex, width: request.size.width,
                      height: request.size.height, template: request.template,
                      objects: try PageElementsCodec.encode(elements), pdfWidth: request.pdfContentSize.map { Double($0.width) }, imageSources: sources)
        try Task.checkCancellation()
        largestKeyBytes = max(largestKeyBytes, key.objects.count)
        if let cached = images.value(for: key) { hits += 1; return cached }
        let background: UIImage?
        if let source = request.pdfPath {
            guard let index = request.pdfIndex else { throw DocumentError.invalidPage }
            background = try await PDFDocumentService.thumbnails.background(path: source, index: index, storage: storage, maxPixels: 180)
        } else { background = nil }
        try Task.checkCancellation()
        let objectImages = try await PageImageService.load(elements, storage: storage, maximumPixelSize: 180)
        renders += 1
        let image = try autoreleasepool {
            let drawing: PKDrawing?
            if ink != nil { drawing = try PKDrawing(data: Data(contentsOf: inkURL)) } else { drawing = nil }
            // Fixed output pixels, even for very large source PDFs. Logical ink coordinates do not change.
            let scale = 180 / max(request.size.width, request.size.height)
            let size = CGSize(width: max(1, floor(request.size.width * scale)), height: max(1, floor(request.size.height * scale)))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                renderer.cgContext.setFillColor(UIColor.white.cgColor)
                renderer.cgContext.fill(CGRect(origin: .zero, size: size))
                renderer.cgContext.scaleBy(x: scale, y: scale)
                PDFRendering.paper(request.template, size: request.size, in: renderer.cgContext)
                if let background { background.draw(in: CGRect(origin: .zero, size: request.pdfContentSize ?? request.size)) }
                PageElementRenderer.draw(elements.filter { $0.kind != .tape }, images: objectImages, in: renderer.cgContext)
                drawing?.image(from: CGRect(origin: .zero, size: request.size), scale: scale)
                    .draw(in: CGRect(origin: .zero, size: request.size))
                PageElementRenderer.draw(elements.filter { $0.kind == .tape }, images: [:], in: renderer.cgContext)
            }
        }
        try Task.checkCancellation()
        if let cg = image.cgImage { images.insert(image, for: key, cost: cg.bytesPerRow * cg.height + key.objects.count) }
        return image
    }
}
