import XCTest
import SwiftData
import PDFKit
import PencilKit
@testable import NotesApp

@MainActor final class PDFDocumentTests: XCTestCase {
    private func fixture(at url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        try renderer.writePDF(to: url) { context in
            for size in [CGSize(width: 200, height: 300), CGSize(width: 400, height: 200), CGSize(width: 200, height: 300)] {
                context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                UIColor.red.setFill(); context.fill(CGRect(x: 20, y: 20, width: 40, height: 40))
                ("Lecture" as NSString).draw(at: CGPoint(x: 80, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        let document = try XCTUnwrap(PDFDocument(url: url))
        document.page(at: 1)?.setBounds(CGRect(x: 20, y: 10, width: 360, height: 180), for: .cropBox)
        document.page(at: 2)?.rotation = 90
        XCTAssertTrue(document.write(to: url))
    }

    func testImportExportPreservesSourceDimensionsRotationInkAndText() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Lecture.pdf")
        try fixture(at: source)
        let original = try Data(contentsOf: source)
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let imported = try await PDFDocumentService.shared.importDocument(from: source, notebookID: UUID(), storage: storage)
        XCTAssertEqual(imported.pageSizes, [CGSize(width: 200, height: 300), CGSize(width: 360, height: 180), CGSize(width: 300, height: 200)])
        let inkPath = "ink.drawing"
        let points = [CGPoint(x: 40, y: 160), CGPoint(x: 140, y: 160)].enumerated().map { i, point in
            PKStrokePoint(location: point, timeOffset: Double(i) * 0.1, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        try await storage.write(ink.dataRepresentation(), to: inkPath)
        let pages = imported.pageSizes.enumerated().map { index, size in
            ExportPage(size: size, template: .blank, drawingPath: index == 0 ? inkPath : nil, pdfPath: imported.path, pdfIndex: index)
        }
        let export = try await PDFExportService.shared.export(pages: pages, storage: storage)
        defer { try? FileManager.default.removeItem(at: export.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: export))
        XCTAssertEqual(document.pageCount, 3)
        for (index, size) in imported.pageSizes.enumerated() {
            let page = try XCTUnwrap(document.page(at: index))
            XCTAssertEqual(page.bounds(for: .mediaBox).size, size)
            XCTAssertTrue(page.string?.contains("Lecture") == true)
        }
        let first = try XCTUnwrap(document.page(at: 0))
        let firstImage = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: unitScale()).image {
            PDFRendering.draw(first, size: CGSize(width: 200, height: 300), in: $0.cgContext)
        }
        let blue = pixel(firstImage, x: 90, y: 160)
        XCTAssertGreaterThan(blue.2, 180); XCTAssertLessThan(blue.0, 100)
        let rotated = try await PDFDocumentService.shared.background(path: imported.path, index: 2, storage: storage, maxPixels: 300)
        let red = pixel(rotated, x: 260, y: 40)
        XCTAssertGreaterThan(red.0, 180); XCTAssertLessThan(red.1, 100)
        let rotatedExport = document.page(at: 2)!
        let rotatedImage = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: unitScale()).image {
            PDFRendering.draw(rotatedExport, size: CGSize(width: 300, height: 200), in: $0.cgContext)
        }
        let exportedRed = pixel(rotatedImage, x: 260, y: 40)
        XCTAssertGreaterThan(exportedRed.0, 180); XCTAssertLessThan(exportedRed.1, 100)
        let croppedImage = try await PDFDocumentService.shared.background(path: imported.path, index: 1, storage: storage, maxPixels: 360)
        let croppedRed = pixel(croppedImage, x: 20, y: 30)
        XCTAssertGreaterThan(croppedRed.0, 180); XCTAssertLessThan(croppedRed.1, 100)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let copy = try await storage.read(imported.path)
        XCTAssertEqual(copy, original)
    }

    func testExportNotebookPaperAndSinglePageAndRejectMissingInk() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let page = ExportPage(size: CGSize(width: 768, height: 1086), template: .grid, drawingPath: nil, pdfPath: nil, pdfIndex: nil)
        let url = try await PDFExportService.shared.export(pages: [page], storage: storage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, page.size)
        let image = UIGraphicsImageRenderer(size: page.size, format: unitScale()).image {
            PDFRendering.draw(document.page(at: 0)!, size: page.size, in: $0.cgContext)
        }
        let line = pixel(image, x: 24, y: 25), white = pixel(image, x: 35, y: 35)
        XCTAssertLessThan(line.0, white.0)
        do {
            _ = try await PDFExportService.shared.export(pages: [ExportPage(size: CGSize(width: CGFloat.nan, height: 100), template: .blank, drawingPath: nil, pdfPath: nil, pdfIndex: nil)], storage: storage)
            XCTFail("Invalid geometry must be rejected before creating a renderer")
        } catch { }
        do {
            _ = try await PDFExportService.shared.export(pages: [ExportPage(size: page.size, template: .blank, drawingPath: "missing", pdfPath: nil, pdfIndex: nil)], storage: storage)
            XCTFail("A missing drawing must never export as an empty page")
        } catch { }
    }

    func testCorruptAndLockedPDFsAreRejected() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("bad.pdf")
        try Data([0, 1, 2]).write(to: url)
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        do {
            _ = try await PDFDocumentService.shared.importDocument(from: url, notebookID: UUID(), storage: storage)
            XCTFail("Corrupt PDF was accepted")
        } catch { }
        try fixture(at: url)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let locked = root.appendingPathComponent("locked.pdf")
        XCTAssertTrue(document.write(to: locked, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "secret"]))
        do {
            _ = try await PDFDocumentService.shared.importDocument(from: locked, notebookID: UUID(), storage: storage)
            XCTFail("Locked PDF was accepted")
        } catch { }
    }

    func testLibraryPDFCopyAndEditorUseIndependentSources() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Lecture.pdf")
        try fixture(at: source)
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        await model.importPDF(from: source, folder: nil, storage: storage)
        XCTAssertNil(model.errorMessage)
        let original = try XCTUnwrap(model.notebooks.first)
        XCTAssertEqual(original.pages.count, 3)
        await model.duplicate(original)
        let copy = try XCTUnwrap(model.notebooks.first { $0.id != original.id })
        let originalPath = try XCTUnwrap(original.orderedPages[0].pdfFilePath)
        let copiedPath = try XCTUnwrap(copy.orderedPages[0].pdfFilePath)
        XCTAssertNotEqual(originalPath, copiedPath)
        let originalData = try await storage.read(originalPath), copyData = try await storage.read(copiedPath)
        XCTAssertEqual(originalData, copyData)
        XCTAssertEqual(Set(copy.pages.compactMap(\.pdfFilePath)).count, 1)
        let session = EditorSession(notebook: copy, context: container.mainContext, storage: storage)
        await session.open(copy.orderedPages[2])
        XCTAssertTrue(session.ready)
        XCTAssertNotNil(session.pdfBackground)
        XCTAssertEqual(session.page?.logicalSize.width, 300)
        XCTAssertEqual(session.page?.logicalSize.height, 200)
        await session.addPage()
        XCTAssertNil(session.page?.pdfFilePath)
        XCTAssertEqual(session.page?.logicalSize.width, 300)
        let result = await session.export(currentPageOnly: false)
        let url = try XCTUnwrap(result)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 4)
    }

    private func unitScale() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> (Int, Int, Int) {
        let cg = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let offset = (y * cg.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}
