import XCTest
import PencilKit
import ImageIO
import UniformTypeIdentifiers
@testable import NotesApp

@MainActor final class ThumbnailOptimizationTests: XCTestCase {
    func testThumbnailImagesDecodeAtOutputSizeAndRespectExifOrientation() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1500), format: format).image {
            UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1000, height: 1500))
            UIColor.blue.setFill(); $0.fill(CGRect(x: 1000, y: 0, width: 1000, height: 1500))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try await storage.write(bytes as Data, to: "photo.jpg")
        var item = PageElement(kind: .image, rect: CGRect(x: 0, y: 0, width: 150, height: 200)); item.imagePath = "photo.jpg"
        let full = try await PageImageService.load([item], storage: storage)
        let bounded = try await PageImageService.load([item, item], storage: storage, maximumPixelSize: 180)
        let original = try XCTUnwrap(full["photo.jpg"]?.cgImage), thumbnail = try XCTUnwrap(bounded["photo.jpg"]?.cgImage)
        XCTAssertEqual(max(original.width, original.height), 2000)
        XCTAssertEqual(thumbnail.width, 135); XCTAssertEqual(thumbnail.height, 180)
        XCTAssertEqual(bounded.count, 1)
        XCTAssertEqual(bounded["photo.jpg"]?.imageOrientation, .up)
        print("THUMBNAIL_OPTIMIZATION photo_full_bytes=\(original.bytesPerRow * original.height) photo_preview_bytes=\(thumbnail.bytesPerRow * thumbnail.height)")
        let retained = try await storage.read("photo.jpg"); XCTAssertEqual(retained, bytes as Data)
    }

    func testOnlyVisibleEditsInvalidateThumbnailsAndRawCorruptionIsNotHidden() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        var text = PageElement(kind: .text, rect: CGRect(x: 30, y: 50, width: 400, height: 60))
        text.text = "Visible text"; text.originalInk = Data(repeating: 2, count: 256 * 1024)
        var request = ThumbnailRequest(size: CGSize(width: 768, height: 1086), template: .ruled,
            drawingPath: nil, fallbackPath: "blank.drawing", pdfPath: nil, pdfIndex: nil, objectsData: try PageElementsCodec.encode([text]))
        let service = PageThumbnailService()
        let first = try await service.thumbnail(request, storage: storage)
        text.originalInk = Data(repeating: 3, count: 256 * 1024); text.originalInkAnchorX = 5
        request.objectsData = try PageElementsCodec.encode([text])
        let same = try await service.thumbnail(request, storage: storage)
        XCTAssertTrue(first === same)
        text.text = "Changed text"; request.objectsData = try PageElementsCodec.encode([text])
        let changed = try await service.thumbnail(request, storage: storage)
        XCTAssertFalse(first === changed)
        XCTAssertNotEqual(first.pngData(), changed.pngData())
        request.objectsData = Data("broken metadata".utf8)
        do { _ = try await service.thumbnail(request, storage: storage); XCTFail("A warmed cache must not hide corruption") } catch {}
        request.objectsData = nil; text.originalInkAnchorY = .infinity; request.elements = [text]
        do { _ = try await service.thumbnail(request, storage: storage); XCTFail("Ignored recovery fields still require validation") } catch {}
        let stats = await service.statistics()
        XCTAssertEqual(stats.renders, 2); XCTAssertEqual(stats.hits, 1)
        XCTAssertLessThan(stats.largestKeyBytes, 4096)
        await service.clearCache()
        let cleared = await service.statistics(); XCTAssertEqual(cleared.cachedImages, 0)
    }

    func testMissingReplacedAndCorruptImagesNeverBecomeCachedSuccesses() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        func photo(_ color: UIColor) throws -> Data {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format).image {
                color.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            }.jpegData(compressionQuality: 0.9))
        }
        var item = PageElement(kind: .image, rect: CGRect(x: 40, y: 50, width: 500, height: 350)); item.imagePath = "photo.jpg"
        try await storage.write(photo(.red), to: "photo.jpg")
        let request = ThumbnailRequest(size: CGSize(width: 768, height: 1086), template: .blank,
            drawingPath: nil, fallbackPath: "blank.drawing", pdfPath: nil, pdfIndex: nil, elements: [item])
        let service = PageThumbnailService(), first = try await service.thumbnail(request, storage: storage)
        try await storage.write(photo(.blue), to: "photo.jpg")
        let replaced = try await service.thumbnail(request, storage: storage)
        XCTAssertNotEqual(first.pngData(), replaced.pngData())
        try await storage.write(Data([1, 2, 3]), to: "photo.jpg")
        do { _ = try await service.thumbnail(request, storage: storage); XCTFail("Corrupt image") } catch {}
        let url = try await storage.fileURL(for: "photo.jpg"); try FileManager.default.removeItem(at: url)
        do { _ = try await service.thumbnail(request, storage: storage); XCTFail("Missing image") } catch {}
        let cancelled = Task { () throws -> [String: UIImage] in
            try Task.checkCancellation()
            return try await PageImageService.load([item], storage: storage, maximumPixelSize: 180)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled image load") } catch is CancellationError {} catch { XCTFail("Expected cancellation: \(error)") }
    }

    func testCacheBudgetIncludesEncodedKeysAndEvictsWithoutChangingSources() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root), service = PageThumbnailService()
        var text = PageElement(kind: .text, rect: CGRect(x: 30, y: 40, width: 400, height: 50))
        let archive = Data(repeating: 4, count: 256 * 1024); text.originalInk = archive
        text.text = "Page 0"
        var request = ThumbnailRequest(size: CGSize(width: 768, height: 1086), template: .blank,
            drawingPath: nil, fallbackPath: "blank.drawing", pdfPath: nil, pdfIndex: nil, elements: [text])
        let first = try await service.thumbnail(request, storage: storage)
        let initial = await service.statistics()
        let pixels = try XCTUnwrap(first.cgImage)
        XCTAssertGreaterThan(initial.estimatedBytes, pixels.bytesPerRow * pixels.height, "Encoded keys belong to the cache estimate too")
        // The renderer may choose different bitmap formats. Exceed the entry limit
        // as well as exercising the byte limit, rather than assuming bytes per pixel.
        for index in 1..<160 {
            text.text = "Page \(index)"; request.elements = [text]
            _ = try await service.thumbnail(request, storage: storage)
        }
        let stats = await service.statistics()
        XCTAssertLessThanOrEqual(stats.estimatedBytes, 4 * 1024 * 1024)
        XCTAssertLessThan(stats.cachedImages, 160)
        XCTAssertEqual(text.originalInk, archive)
        text.text = "Page 0"; request.elements = [text]
        let reloaded = try await service.thumbnail(request, storage: storage)
        XCTAssertFalse(reloaded === first); XCTAssertEqual(reloaded.pngData(), first.pngData())
    }

    func testRepeatedRichThumbnailWorkload() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        try await storage.write(PKDrawing().dataRepresentation(), to: "ink.drawing")
        let archive = Data(repeating: 41, count: 256 * 1024)
        let elements = (0..<12).map { index in
            var text = PageElement(kind: .text, rect: CGRect(x: 50, y: 40 + index * 60, width: 500, height: 50))
            text.text = "Lecture note \(index)"; text.originalInk = archive
            return text
        }
        let request = ThumbnailRequest(size: CGSize(width: 768, height: 1086), template: .ruled,
            drawingPath: "ink.drawing", fallbackPath: "ink.drawing", pdfPath: nil, pdfIndex: nil, elements: elements)
        let service = PageThumbnailService()
        let first = try await service.thumbnail(request, storage: storage)
        let clock = ContinuousClock(), start = clock.now
        for _ in 0..<8 {
            let result = try await service.thumbnail(request, storage: storage)
            XCTAssertTrue(first === result)
        }
        let elapsed = start.duration(to: clock.now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        let encoded = try PageElementsCodec.encode(elements)
        print("THUMBNAIL_OPTIMIZATION rich_cache_hits_8_ms=\(ms) source_metadata_bytes=\(encoded.count)")
        XCTAssertEqual(elements[0].originalInk, archive)
        let stats = await service.statistics()
        XCTAssertEqual(stats.renders, 1); XCTAssertEqual(stats.hits, 8)
        XCTAssertLessThan(stats.largestKeyBytes, 16 * 1024)
        XCTAssertLessThanOrEqual(stats.estimatedBytes, 4 * 1024 * 1024)
        print("THUMBNAIL_OPTIMIZATION visible_key_bytes=\(stats.largestKeyBytes) retained_estimate=\(stats.estimatedBytes)")
    }
}
