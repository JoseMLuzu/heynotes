import XCTest
import ImageIO
@testable import NotesApp

@MainActor final class StudyImageLoaderTests: XCTestCase {
    func testDecodedImagesAreBoundedCachedAndNeverHideMissingOrReplacedFiles() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("StudyImages-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root), loader = StudyImageLoader()
        let data = try imageData(.red)
        try await storage.write(data, to: "capture.png")
        let a = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900)
        let b = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900)
        XCTAssertTrue(a === b)
        XCTAssertLessThanOrEqual(max(a.cgImage!.width, a.cgImage!.height), 900)
        var stats = await loader.statistics()
        XCTAssertEqual(stats.decodes, 1); XCTAssertEqual(stats.hits, 1); XCTAssertEqual(stats.mainThreadDecodes, 0)
        XCTAssertLessThanOrEqual(stats.imageBytes, 16 * 1_048_576)
        let original = try await storage.read("capture.png")
        XCTAssertEqual(original, data); XCTAssertEqual(UIImage(data: original)?.cgImage?.width, 2400)
        await loader.clearCache(); stats = await loader.statistics()
        XCTAssertEqual(stats.imageBytes, 0); XCTAssertEqual(stats.imageCount, 0)
        _ = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900)
        try await storage.write(imageData(.blue), to: "capture.png")
        _ = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900)
        stats = await loader.statistics(); XCTAssertEqual(stats.decodes, 3)
        let url = try await storage.fileURL(for: "capture.png")
        try FileManager.default.removeItem(at: url)
        do { _ = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900); XCTFail("Missing file cannot be a cache success") } catch {}
        try await storage.write(Data([1, 2, 3]), to: "capture.png")
        do { _ = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900); XCTFail("Corruption must remain visible") } catch {}
    }

    func testCacheBudgetsCancellationAndSeparateStorageRoots() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("StudyImageBudget-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = DrawingStorage(root: root.appendingPathComponent("A")), b = DrawingStorage(root: root.appendingPathComponent("B"))
        let loader = StudyImageLoader(byteLimit: 100_000)
        try await a.write(imageData(.red), to: "same.png"); try await b.write(imageData(.blue), to: "same.png")
        let first = try await loader.image(path: "same.png", storage: a, maxPixels: 100)
        let other = try await loader.image(path: "same.png", storage: b, maxPixels: 100)
        XCTAssertFalse(first === other)
        _ = try await loader.image(path: "same.png", storage: a, maxPixels: 100)
        var stats = await loader.statistics(); XCTAssertEqual(stats.decodes, 2); XCTAssertEqual(stats.hits, 1)
        _ = try await loader.image(path: "same.png", storage: a, maxPixels: 900)
        stats = await loader.statistics(); XCTAssertLessThanOrEqual(stats.imageBytes, 100_000)
        let cancelledLoader = StudyImageLoader()
        let task = Task { try await cancelledLoader.image(path: "same.png", storage: a, maxPixels: 900) }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled load must not publish an image") } catch is CancellationError {} catch { XCTFail("Unexpected error \(error)") }
        let cancelled = await cancelledLoader.statistics(); XCTAssertEqual(cancelled.decodes, 0); XCTAssertEqual(cancelled.imageCount, 0)
    }

    func testRepeatedCardImageWorkload() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("StudyImagePerf-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root), loader = StudyImageLoader()
        try await storage.write(imageData(.black), to: "capture.png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 675), format: format)
        let clock = ContinuousClock(), before = clock.now
        for _ in 0..<3 {
            let data = try await storage.read("capture.png")
            let image = try XCTUnwrap(UIImage(data: data))
            _ = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 900, height: 675)) }
        }
        let legacy = before.duration(to: clock.now), after = clock.now
        for _ in 0..<3 {
            let image = try await loader.image(path: "capture.png", storage: storage, maxPixels: 900)
            _ = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 900, height: 675)) }
        }
        let optimized = after.duration(to: clock.now)
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        let stats = await loader.statistics(); XCTAssertEqual(stats.decodes, 1); XCTAssertEqual(stats.hits, 2)
        XCTAssertEqual(stats.mainThreadDecodes, 0)
        print("PERFORMANCE study_image_3_display_requests_legacy_ms=\(milliseconds(legacy)) optimized_ms=\(milliseconds(optimized))")
        let attachment = XCTAttachment(string: "3 displays of a 2400×1800 PNG at 900×675 pixels: legacy \(milliseconds(legacy)) ms; downsample/cache \(milliseconds(optimized)) ms. Simulator only.")
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func imageData(_ color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
            for index in 0..<40 {
                ("Handwritten region, equation and study answer \(index)" as NSString).draw(at: CGPoint(x: 30, y: 30 + index * 40),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.white])
            }
        }
        return try XCTUnwrap(image.pngData())
    }
}
