import Foundation
import PencilKit
import PDFKit
import UIKit

struct ExportPage: Sendable {
    let size: CGSize
    let template: PaperTemplate
    let drawingPath: String?
    let pdfPath: String?
    let pdfIndex: Int?
    var pdfContentSize: CGSize? = nil
    var elements: [PageElement] = []
    var includeStudyTape = false
}

protocol PDFExporting: Sendable {
    func export(pages: [ExportPage], storage: DrawingStorage) async throws -> URL
}

actor PDFExportService: PDFExporting {
    static let shared = PDFExportService()

    func export(pages: [ExportPage], storage: DrawingStorage = .shared) async throws -> URL {
        guard !pages.isEmpty else { throw DocumentError.emptyExport }
        guard pages.allSatisfy({ $0.size.width.isFinite && $0.size.height.isFinite &&
            $0.size.width >= 1 && $0.size.height >= 1 && $0.size.width <= 14400 && $0.size.height <= 14400 })
        else { throw DocumentError.invalidPage }
        var drawingURLs: [URL?] = [], pdfURLs: [URL?] = []
        for page in pages {
            if let path = page.drawingPath { drawingURLs.append(try await storage.fileURL(for: path)) }
            else { drawingURLs.append(nil) }
            if let path = page.pdfPath { pdfURLs.append(try await storage.fileURL(for: path)) }
            else { pdfURLs.append(nil) }
        }
        var imageURLs: [String: URL] = [:]
        for page in pages {
            for path in Set(page.elements.compactMap(\.imagePath)) { imageURLs[path] = try await storage.fileURL(for: path) }
        }
        let directory = URL.temporaryDirectory.appendingPathComponent("NotesExports/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Notes.pdf")
        var currentPDFURL: URL?
        var currentPDF: PDFDocument?
        var failure: Error?
        do {
            try UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pages[0].size)).writePDF(to: url) { renderer in
                for (index, descriptor) in pages.enumerated() {
                    do {
                        try autoreleasepool {
                            guard descriptor.size.width > 0, descriptor.size.height > 0 else { throw DocumentError.invalidPage }
                            renderer.beginPage(withBounds: CGRect(origin: .zero, size: descriptor.size), pageInfo: [:])
                            let context = renderer.cgContext
                            var objectImages: [String: UIImage] = [:]
                            for path in Set(descriptor.elements.compactMap(\.imagePath)) {
                                guard let imageURL = imageURLs[path], let image = UIImage(data: try Data(contentsOf: imageURL)) else { throw PageElementError.unreadable }
                                objectImages[path] = image
                            }
                            PDFRendering.paper(descriptor.template, size: descriptor.size, in: context)
                            if let pdfURL = pdfURLs[index], let sourceIndex = descriptor.pdfIndex {
                                if currentPDFURL != pdfURL {
                                    currentPDF = try PDFRendering.open(pdfURL)
                                    currentPDFURL = pdfURL
                                }
                                guard let page = currentPDF?.page(at: sourceIndex) else { throw DocumentError.invalidPage }
                                PDFRendering.draw(page, size: descriptor.pdfContentSize ?? descriptor.size, in: context)
                            } else {
                                guard descriptor.pdfPath == nil else { throw DocumentError.invalidPage }
                            }
                            PageElementRenderer.draw(descriptor.elements.filter { $0.kind != .tape }, images: objectImages, in: context)
                            if let drawingURL = drawingURLs[index] {
                                let drawing = try PKDrawing(data: Data(contentsOf: drawingURL))
                                // PencilKit exposes editable strokes and bitmap rendering, not a public vector PDF API.
                                // Bound the temporary raster per page rather than loading a whole notebook in RAM.
                                let scale = min(2, 4096 / max(descriptor.size.width, descriptor.size.height))
                                drawing.image(from: CGRect(origin: .zero, size: descriptor.size), scale: scale)
                                    .draw(in: CGRect(origin: .zero, size: descriptor.size))
                            }
                            if descriptor.includeStudyTape {
                                PageElementRenderer.draw(descriptor.elements.filter { $0.kind == .tape }, images: [:], in: context)
                            }
                        }
                    } catch { failure = error; break }
                }
            }
            if let failure { throw failure }
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory) // Only this failed export's temporary artifacts.
            throw error
        }
    }
}
