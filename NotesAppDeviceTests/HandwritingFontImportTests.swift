import XCTest
import UIKit
import PDFKit
@testable import NotesApp

@MainActor final class HandwritingFontImportTests: XCTestCase {
    func testImportsRealFontDeduplicatesReloadsReferencesAndExportsSelectableText() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Personal.ttf"), storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        try HandwritingTestFont.data.write(to: source)
        let store = HandwritingFontStore.shared
        let font = try await store.importFont(from: source, storage: storage)
        XCTAssertEqual(font.name, HandwritingTestFont.name)
        XCTAssertTrue(font.path.hasPrefix("Fonts/")); XCTAssertFalse(font.path.hasPrefix("/"))
        XCTAssertEqual(HandwritingFont.resolve(font.name, size: 24).fontName, font.name)
        let duplicate = try await store.importFont(from: source, storage: storage)
        XCTAssertEqual(duplicate.path, font.path)
        let catalog = try await store.catalog(storage: storage)
        XCTAssertEqual(catalog.count, 1)
        try FileManager.default.removeItem(at: source)
        var text = PageElement(kind: .text, rect: CGRect(x: 40, y: 60, width: 200, height: 80))
        text.text = "A"; text.fontName = font.name; text.fontFilePath = font.path; text.fontSize = 32
        let reopened = try PageElementsCodec.decode(PageElementsCodec.encode([text]))
        try await store.prepare(reopened, storage: storage)
        let request = PagePreparationRequest(pageID: UUID(), source: PageLoadRequest(drawingPath: nil,
            fallbackDrawingPath: "blank.drawing", pdfPath: nil, pdfIndex: nil), objectsData: try PageElementsCodec.encode(reopened))
        let pages = PagePreparationService()
        _ = try await pages.content(request, storage: storage)
        let bytes = try await storage.read(font.path)
        XCTAssertEqual(bytes, HandwritingTestFont.data)
        // Backup restore paths need no external file-provider URL or catalog entry.
        let restored = "Restored/\(UUID())/\(font.path)"
        try await storage.write(bytes, to: restored); text.fontFilePath = restored
        let recoveredCatalog = try await store.catalog(storage: storage)
        XCTAssertEqual(recoveredCatalog.count, 1)
        try await store.prepare([text], storage: storage)
        let descriptor = ExportPage(size: CGSize(width: 768, height: 1086), template: .ruled, drawingPath: nil,
            pdfPath: nil, pdfIndex: nil, elements: [text])
        let url = try await PDFExportService.shared.export(pages: [descriptor], storage: storage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        XCTAssertTrue(page.string?.contains("A") == true)
        XCTAssertGreaterThan(page.characterBounds(at: 0).height, 0)
        // A warmed page cannot conceal a missing required font asset.
        try FileManager.default.removeItem(at: await storage.fileURL(for: font.path))
        do { _ = try await pages.content(request, storage: storage); XCTFail("Cached page must still validate font existence") } catch {}
        let restoredOnly = try await store.catalog(storage: storage)
        XCTAssertEqual(restoredOnly.first?.path, restored)
    }

    func testInvalidOversizedConflictingAndMissingFontsFailWithoutRemovingAssets() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents")), store = HandwritingFontStore.shared
        let original = root.appendingPathComponent("Good.otf")
        try HandwritingTestFont.data.write(to: original)
        let asset = try await store.importFont(from: original, storage: storage)
        for (name, bytes) in [("Broken.ttf", Data([1, 2, 3])), ("Wrong.txt", HandwritingTestFont.data),
                              ("Large.ttf", Data(repeating: 0, count: 10 * 1024 * 1024 + 1)),
                              ("Conflict.ttf", HandwritingTestFont.data + Data([0, 0, 0, 0]))] {
            let source = root.appendingPathComponent(name); try bytes.write(to: source)
            do { _ = try await store.importFont(from: source, storage: storage); XCTFail("Expected rejection: \(name)") } catch {}
        }
        var text = PageElement(kind: .text, rect: CGRect(x: 20, y: 20, width: 200, height: 80))
        text.fontFilePath = "Fonts/missing.ttf"; text.fontName = asset.name
        do { try await store.prepare([text], storage: storage); XCTFail("Missing font must be reported") } catch {}
        text.fontFilePath = asset.path; text.fontName = "A different name"
        do { try await store.prepare([text], storage: storage); XCTFail("Mismatched font must be reported") } catch {}
        let retained = try await storage.read(asset.path)
        XCTAssertEqual(retained, HandwritingTestFont.data)
    }
}
