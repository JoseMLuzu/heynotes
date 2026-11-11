import XCTest
import PDFKit
import PencilKit
@testable import NotesApp

@MainActor final class PerformanceTests: XCTestCase {
    func testRepeatedPDFPreviewWorkload() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("lecture.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 768, height: 1086)).writePDF(to: source) { context in
            context.beginPage()
            for index in 0..<70 {
                ("Lecture notes: equations, diagrams and ideas to remember." as NSString)
                    .draw(at: CGPoint(x: 30, y: 20 + index * 14), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            }
        }
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let service = PDFDocumentService()
        let imported = try await service.importDocument(from: source, notebookID: UUID(), storage: storage)
        let clock = ContinuousClock()
        let started = clock.now
        for _ in 0..<6 {
            let image = try await service.background(path: imported.path, index: 0, storage: storage)
            XCTAssertNotNil(image.cgImage)
        }
        let duration = started.duration(to: clock.now)
        let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        print("PERFORMANCE repeated_pdf_preview_6_requests_ms=\(milliseconds)")
        let statistics = await service.cacheStatistics()
        XCTAssertEqual(statistics.renders, 1)
        XCTAssertEqual(statistics.documentOpens, 1)
        add(XCTAttachment(string: "Six identical preview requests: \(milliseconds) ms on simulator. No device FPS claim."))
    }
    func testPDFCacheBudgetClearAndMissingOrReplacedSource() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).writePDF(to: source) { context in
            context.beginPage(); UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            context.beginPage(); UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let service = PDFDocumentService(imageByteLimit: 110_000, documentLimit: 1)
        let imported = try await service.importDocument(from: source, notebookID: UUID(), storage: storage)
        for index in [0, 1, 0] {
            _ = try await service.background(path: imported.path, index: index, storage: storage, maxPixels: 180)
            let stats = await service.cacheStatistics()
            XCTAssertLessThanOrEqual(stats.imageBytes, 110_000)
            XCTAssertLessThanOrEqual(stats.imageCount, 1)
        }
        let stats = await service.cacheStatistics()
        XCTAssertEqual(stats.documentOpens, 1)
        await service.clearCaches()
        let cleared = await service.cacheStatistics()
        XCTAssertEqual(cleared.imageBytes, 0)
        XCTAssertEqual(cleared.imageCount, 0)
        _ = try await service.background(path: imported.path, index: 0, storage: storage, maxPixels: 180)
        let replacedURL = try await storage.fileURL(for: imported.path)
        try Data([1, 2, 3]).write(to: replacedURL, options: .atomic)
        do {
            _ = try await service.background(path: imported.path, index: 0, storage: storage, maxPixels: 180)
            XCTFail("A cached page must not hide a replaced/corrupt PDF")
        } catch { }
        try FileManager.default.removeItem(at: replacedURL)
        do {
            _ = try await service.background(path: imported.path, index: 0, storage: storage, maxPixels: 180)
            XCTFail("A cached page must not hide a missing PDF")
        } catch { }
    }

    func testHugePageThumbnailHasBoundedPixelsAndDoesNotMaskMissingInk() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        try await storage.write(PKDrawing().dataRepresentation(), to: "ink.drawing")
        let request = ThumbnailRequest(size: CGSize(width: 14400, height: 14400), template: .grid,
                                       drawingPath: "ink.drawing", fallbackPath: "ink.drawing", pdfPath: nil, pdfIndex: nil)
        let service = PageThumbnailService()
        let first = try await service.thumbnail(request, storage: storage)
        let repeated = try await service.thumbnail(request, storage: storage)
        XCTAssertTrue(first === repeated)
        XCTAssertLessThanOrEqual(first.cgImage!.width, 180)
        XCTAssertLessThanOrEqual(first.cgImage!.height, 180)
        let path = try await storage.fileURL(for: "ink.drawing")
        try FileManager.default.removeItem(at: path)
        do {
            _ = try await service.thumbnail(request, storage: storage)
            XCTFail("A cached thumbnail must not hide missing saved ink")
        } catch { }
    }

}
