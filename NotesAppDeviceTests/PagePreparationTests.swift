import XCTest
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class PagePreparationTests: XCTestCase {
    func testWarmPagesStillRejectReplacedMissingAndCorruptInk() async throws {
        let fixture = try PreparationFixture()
        defer { fixture.cleanup() }
        try await fixture.storage.write(ink(1).dataRepresentation(), to: "ink.drawing")
        let request = fixture.request()
        let service = PagePreparationService()
        let first = try await service.content(request, storage: fixture.storage)
        let reused = try await service.content(request, storage: fixture.storage)
        XCTAssertEqual(first.drawing, reused.drawing)
        XCTAssertEqual(first.identity, reused.identity)
        var stats = await service.statistics()
        XCTAssertEqual(stats.loads, 1); XCTAssertEqual(stats.hits, 1)
        try await fixture.storage.write(ink(2).dataRepresentation(), to: "ink.drawing")
        let replaced = try await service.content(request, storage: fixture.storage)
        XCTAssertEqual(replaced.drawing.strokes.count, 2)
        XCTAssertNotEqual(first.identity, replaced.identity)
        let url = try await fixture.storage.fileURL(for: "ink.drawing")
        try FileManager.default.removeItem(at: url)
        do { _ = try await service.content(request, storage: fixture.storage); XCTFail("A warm page must not hide missing ink") }
        catch { }
        try await fixture.storage.write(Data([0, 1, 2]), to: "ink.drawing")
        do { _ = try await service.content(request, storage: fixture.storage); XCTFail("A warm page must not hide corrupt ink") }
        catch { }
        stats = await service.statistics()
        XCTAssertGreaterThanOrEqual(stats.loads, 3)
    }

    func testChangedMetadataAndImagesInvalidatePreparedPage() async throws {
        let fixture = try PreparationFixture()
        defer { fixture.cleanup() }
        try await fixture.storage.write(ink(1).dataRepresentation(), to: "ink.drawing")
        let red = image(.red), blue = image(.blue)
        try await fixture.storage.write(try XCTUnwrap(red.pngData()), to: "photo.png")
        var element = PageElement(kind: .image, rect: CGRect(x: 10, y: 10, width: 80, height: 80))
        element.imagePath = "photo.png"
        let service = PagePreparationService()
        let request = fixture.request(objects: try PageElementsCodec.encode([element]))
        let first = try await service.content(request, storage: fixture.storage)
        try await fixture.storage.write(try XCTUnwrap(blue.pngData()), to: "photo.png")
        let replacement = try await service.content(request, storage: fixture.storage)
        XCTAssertNotEqual(first.images["photo.png"]?.pngData(), replacement.images["photo.png"]?.pngData())
        var text = PageElement(kind: .text, rect: CGRect(x: 10, y: 100, width: 200, height: 60))
        text.text = "Updated content"
        let changed = PagePreparationRequest(pageID: request.pageID, source: request.source,
            objectsData: try PageElementsCodec.encode([element, text]))
        let updated = try await service.content(changed, storage: fixture.storage)
        XCTAssertEqual(updated.elements.last?.text, "Updated content")
        try await fixture.storage.write(Data([0, 1, 2]), to: "photo.png")
        do { _ = try await service.content(changed, storage: fixture.storage); XCTFail("A warm image must not hide corrupt bytes") }
        catch { }
    }

    func testPreparationHasBoundedWorkingSetAndCanBeCleared() async throws {
        let fixture = try PreparationFixture()
        defer { fixture.cleanup() }
        try await fixture.storage.write(ink(1).dataRepresentation(), to: "ink.drawing")
        let service = PagePreparationService(byteLimit: 1_000_000)
        for _ in 0..<5 { _ = try await service.content(fixture.request(), storage: fixture.storage) }
        let stats = await service.statistics()
        XCTAssertEqual(stats.cachedPages, 3); XCTAssertLessThanOrEqual(stats.estimatedBytes, 1_000_000)
        await service.clear()
        let cleared = await service.statistics()
        XCTAssertEqual(cleared.cachedPages, 0); XCTAssertEqual(cleared.estimatedBytes, 0)
        let tiny = PagePreparationService(byteLimit: 1)
        _ = try await tiny.content(fixture.request(), storage: fixture.storage)
        let limited = await tiny.statistics()
        XCTAssertEqual(limited.cachedPages, 0)
    }

    func testCancelledPreloadDoesNotCancelForegroundConsumerAndClearDoesNotRecache() async throws {
        let fixture = try PreparationFixture()
        defer { fixture.cleanup() }
        let gate = PreparationGate()
        let service = PagePreparationService { request, elements, storage in
            await gate.wait()
            try Task.checkCancellation()
            return try await PagePreparationService.loadPage(request, elements: elements, storage: storage)
        }
        let request = fixture.request()
        let prefetch = Task { try await service.content(request, storage: fixture.storage) }
        try await waitForConsumers(1, in: service)
        let foreground = Task { try await service.content(request, storage: fixture.storage) }
        try await waitForConsumers(2, in: service)
        prefetch.cancel()
        try await waitForConsumers(1, in: service)
        await service.clear()
        await gate.release()
        let loaded = try await foreground.value
        XCTAssertEqual(loaded.drawing.strokes.count, 0)
        do { _ = try await prefetch.value; XCTFail("Cancelled prefetch should stop") }
        catch is CancellationError { } catch { XCTFail("Unexpected cancellation error: \(error)") }
        let stats = await service.statistics()
        XCTAssertEqual(stats.loads, 1); XCTAssertEqual(stats.cachedPages, 0); XCTAssertEqual(stats.consumers, 0)
    }

    func testSessionPreparesNeighborsAndStillSavesNewestInkBeforeReturning() async throws {
        let fixture = try PreparationFixture()
        defer { fixture.cleanup() }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Prepared notebook")
        container.mainContext.insert(notebook)
        for index in 0..<3 {
            let page = NotePage(pageIndex: index)
            container.mainContext.insert(page); notebook.pages.append(page)
        }
        try container.mainContext.save()
        let ordered = notebook.orderedPages
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: fixture.storage)
        defer { session.stopPreparingPages(); withExtendedLifetime(container) {} }
        await session.open(ordered[1])
        for _ in 0..<100 {
            let stats = await session.pagePreparation.statistics()
            if stats.cachedPages == 3 && stats.consumers == 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let prepared = await session.pagePreparation.statistics()
        XCTAssertEqual(prepared.cachedPages, 3)
        await session.turnPage(1)
        XCTAssertEqual(session.page?.id, ordered[2].id)
        let reused = await session.pagePreparation.statistics()
        XCTAssertEqual(reused.loads, prepared.loads)
        XCTAssertGreaterThan(reused.hits, prepared.hits)
        session.changed(ink(3))
        await session.turnPage(-1)
        await session.turnPage(1)
        XCTAssertEqual(session.drawing.strokes.count, 3)
        let saved = try await fixture.storage.read(try XCTUnwrap(ordered[2].drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: saved).strokes.count, 3)
    }

    func testRepeatedWarmPreparationAvoidsDrawingAndRichContentDecoding() async throws {
        let fixture = try PreparationFixture()
        defer { fixture.cleanup() }
        try await fixture.storage.write(ink(20).dataRepresentation(), to: "ink.drawing")
        var text = PageElement(kind: .text, rect: CGRect(x: 20, y: 20, width: 300, height: 80))
        text.text = "Lecture notes"; text.originalInk = Data(repeating: 42, count: 150_000)
        let request = fixture.request(objects: try PageElementsCodec.encode([text]))
        let start = ContinuousClock.now
        for _ in 0..<20 {
            let elements = try await PageLoader.elements(request.objectsData)
            _ = try await PagePreparationService.loadPage(request, elements: elements, storage: fixture.storage)
        }
        let cold = start.duration(to: .now)
        let service = PagePreparationService()
        _ = try await service.content(request, storage: fixture.storage)
        let warmStart = ContinuousClock.now
        for _ in 0..<20 { _ = try await service.content(request, storage: fixture.storage) }
        let warm = warmStart.duration(to: .now)
        let stats = await service.statistics()
        XCTAssertEqual(stats.loads, 1); XCTAssertEqual(stats.hits, 20)
        let result = "20 page loads: unprepared \(milliseconds(cold)) ms; prepared \(milliseconds(warm)) ms. One prepared load, 20 reuse hits. Simulator workload, not device FPS."
        print("PAGE_PREPARATION \(result)")
        add(XCTAttachment(string: result))
    }

    private func waitForConsumers(_ count: Int, in service: PagePreparationService) async throws {
        for _ in 0..<200 {
            if await service.statistics().consumers == count { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Shared preparation did not reach \(count) consumers")
    }
    private func ink(_ count: Int) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { index in
            let points = [CGPoint(x: 20, y: 40 + index * 5), CGPoint(x: 180, y: 90 + index * 5)].enumerated().map {
                PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                              size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))
        })
    }
    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image {
            color.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
    }
    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}

private actor PreparationGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() { opened = true; let waiting = continuations; continuations = []; waiting.forEach { $0.resume() } }
}

private struct PreparationFixture {
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let storage: DrawingStorage
    init() throws { storage = DrawingStorage(root: root) }
    func request(objects: Data? = nil) -> PagePreparationRequest {
        // Missing fallback ink is a legitimate new blank page; explicit ink paths are not.
        let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent("ink.drawing").path)
        return PagePreparationRequest(pageID: UUID(),
            source: PageLoadRequest(drawingPath: exists ? "ink.drawing" : nil, fallbackDrawingPath: "ink.drawing", pdfPath: nil, pdfIndex: nil), objectsData: objects)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
