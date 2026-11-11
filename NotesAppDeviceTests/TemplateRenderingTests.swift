import XCTest
import PDFKit
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class TemplateRenderingTests: XCTestCase {
    func testEveryTemplateRendersAndExportsWithPageDimensions() async throws {
        let pages = PaperTemplate.allCases.map {
            ExportPage(size: CGSize(width: 768, height: 1086), template: $0, drawingPath: nil, pdfPath: nil, pdfIndex: nil)
        }
        let url = try await PDFExportService.shared.export(pages: pages, storage: .shared)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 16)
        for (index, template) in PaperTemplate.allCases.enumerated() {
            let page = try XCTUnwrap(document.page(at: index))
            XCTAssertEqual(page.bounds(for: .mediaBox).size, pages[index].size)
            let image = render(template, size: pages[index].size, scale: 0.2)
            XCTAssertNotNil(image.cgImage)
            if template == .cornell || template == .lecture || template == .dailyPlanner {
                XCTAssertTrue(page.string?.contains(template.title) == true)
            }
            if template == .cornell || template == .dailyPlanner || template == .weeklyPlanner {
                let attachment = XCTAttachment(image: image)
                attachment.name = "Template-\(template.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testStructuredTemplatePreservesInkCoordinatesInExport() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let points = [CGPoint(x: 100, y: 600), CGPoint(x: 300, y: 600)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
        try await storage.write(ink.dataRepresentation(), to: "ink.drawing")
        let descriptor = ExportPage(size: CGSize(width: 768, height: 1086), template: .cornell, drawingPath: "ink.drawing", pdfPath: nil, pdfIndex: nil)
        let url = try await PDFExportService.shared.export(pages: [descriptor], storage: storage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: descriptor.size, format: format).image {
            PDFRendering.draw(page, size: descriptor.size, in: $0.cgContext)
        }
        let blue = pixel(image, x: 200, y: 600)
        XCTAssertGreaterThan(blue.2, 180); XCTAssertLessThan(blue.0, 100)
        let header = pixel(image, x: 60, y: 130)
        XCTAssertLessThan(header.0, 250); XCTAssertGreaterThan(header.2, 230)
        let original = try await storage.read("ink.drawing")
        XCTAssertEqual(original, ink.dataRepresentation())
    }

    func testChangingTemplateKeepsDrawingAndNewPagesInheritIt() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = LibraryViewModel(context: container.mainContext, storage: storage)
        XCTAssertTrue(model.createNotebook(title: "Study", color: .sage, template: .cornell, folder: nil))
        let notebook = try XCTUnwrap(model.notebooks.first), page = try XCTUnwrap(notebook.pages.first)
        let id = page.id
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        session.changed(PKDrawing())
        let success = await session.flush()
        XCTAssertTrue(success)
        let path = try XCTUnwrap(page.drawingFilePath), before = try await storage.read(path)
        let previousDate = notebook.updatedAt
        session.changeTemplate(.cornell)
        XCTAssertEqual(notebook.updatedAt, previousDate)
        session.changeTemplate(.weeklyPlanner)
        XCTAssertEqual(page.id, id)
        XCTAssertEqual(page.drawingFilePath, path)
        let after = try await storage.read(path)
        XCTAssertEqual(before, after)
        await session.addPage()
        XCTAssertEqual(session.page?.paperTemplate, .weeklyPlanner)
        session.page?.pdfFilePath = "source.pdf"
        session.changeTemplate(.grid)
        XCTAssertEqual(session.page?.paperTemplate, .weeklyPlanner) // Never replace a PDF's background.
    }

    private func render(_ template: PaperTemplate, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image {
            TemplateRenderer.draw(template, size: size, in: $0.cgContext)
        }
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
