import PDFKit
import UIKit

struct CapturedPage: Identifiable, Sendable {
    let id = UUID()
    let source: StudySource
    let title: String
    let size: CGSize
    let png: Data
}

actor PageCaptureService {
    static let shared = PageCaptureService()

    func capture(_ page: ExportPage, source: StudySource, title: String, storage: DrawingStorage) async throws -> CapturedPage {
        let pdf = try await PDFExportService.shared.export(pages: [page], storage: storage)
        defer { try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent()) }
        guard let document = PDFDocument(url: pdf), let pdfPage = document.page(at: 0) else { throw DocumentError.unreadable }
        let scale = min(2, 2048 / max(page.size.width, page.size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        let image = UIGraphicsImageRenderer(size: page.size, format: format).image { renderer in
            PDFRendering.draw(pdfPage, size: page.size, in: renderer.cgContext)
        }
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return CapturedPage(source: source, title: title, size: page.size, png: data)
    }

    func crop(_ data: Data, normalized region: CGRect) throws -> Data {
        guard let image = UIImage(data: data)?.cgImage, image.width <= 4096, image.height <= 4096,
              [region.minX, region.minY, region.width, region.height].allSatisfy(\.isFinite) else { throw PageElementError.unreadable }
        let region = region.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !region.isNull, region.width > 0, region.height > 0 else { throw PageElementError.invalid }
        let pixels = CGRect(x: region.minX * Double(image.width), y: region.minY * Double(image.height),
                            width: region.width * Double(image.width), height: region.height * Double(image.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard pixels.width >= 2, pixels.height >= 2, let cropped = image.cropping(to: pixels),
              let data = UIImage(cgImage: cropped).pngData() else { throw PageElementError.invalid }
        return data
    }

    func shareFile(_ data: Data) throws -> URL {
        let directory = URL.temporaryDirectory.appendingPathComponent("NotesCaptures/\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Capture.png")
        do { try data.write(to: url, options: .atomic); return url }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}

extension CapturedPage {
    func normalized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / size.width, y: rect.minY / size.height, width: rect.width / size.width, height: rect.height / size.height)
    }
}
