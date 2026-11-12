import XCTest
import SwiftUI
import Observation
import PencilKit
import SwiftData
@testable import NotesApp

final class FluidityDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var writes = 0
    var dataReads: Int { lock.withLock { reads } }
    var dataWrites: Int { lock.withLock { writes } }
    override func data(forKey defaultName: String) -> Data? {
        lock.withLock { reads += 1 }
        return super.data(forKey: defaultName)
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { writes += 1 }
        super.set(value, forKey: defaultName)
    }
}

private final class ChangeCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func record() { lock.lock(); count += 1; lock.unlock() }
}

@MainActor final class FluidityTests: XCTestCase {
    func testEditorPreferenceReadsDuringParentRefreshes() async throws {
        let suite = "EditorRefresh.\(UUID())"
        let defaults = try XCTUnwrap(FluidityDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Refresh"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        func editor() -> some View {
            EditorView(session: session, onLibrary: {}, preferencesDefaults: defaults).modelContainer(container)
        }
        let host = UIHostingController(rootView: editor())
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let canvas = try XCTUnwrap(session.canvas)
        let initialReads = defaults.dataReads, initialWrites = defaults.dataWrites
        let started = ContinuousClock.now
        for _ in 0..<20 {
            host.rootView = editor()
            host.view.layoutIfNeeded()
            await Task.yield()
        }
        let duration = started.duration(to: .now)
        print("FLUIDITY editor_parent_refreshes=20 preference_reads=\(defaults.dataReads - initialReads) writes=\(defaults.dataWrites - initialWrites) duration_ms=\(ms(duration))")
        XCTAssertEqual(defaults.dataReads, initialReads)
        XCTAssertEqual(defaults.dataWrites, initialWrites)
        XCTAssertTrue(session.canvas === canvas)
        withExtendedLifetime(container) {}
    }

    func testStyleChangesDoNotInvalidateToolSelectionOrRulerAndNoOpsStayQuiet() throws {
        let name = "Fluidity.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tools = ToolPreferences(defaults: defaults)
        let selected = ChangeCount(), ink = ChangeCount(), ruler = ChangeCount(), favorites = ChangeCount()
        withObservationTracking { _ = tools.selected } onChange: { selected.record() }
        withObservationTracking { _ = tools.ink } onChange: { ink.record() }
        withObservationTracking { _ = tools.rulerEnabled } onChange: { ruler.record() }
        withObservationTracking { _ = tools.quickColors } onChange: { favorites.record() }
        tools.ink.width = 4.5
        XCTAssertEqual(ink.value, 1)
        XCTAssertEqual(selected.value, 0); XCTAssertEqual(ruler.value, 0); XCTAssertEqual(favorites.value, 0)
        XCTAssertEqual(ToolPreferences(defaults: defaults).ink.width, 4.5)
        let nextInk = ChangeCount()
        withObservationTracking { _ = tools.ink } onChange: { nextInk.record() }
        let unchanged = tools.ink
        tools.ink = unchanged; tools.selected = .pen; tools.rulerEnabled = false
        XCTAssertEqual(nextInk.value, 0); XCTAssertEqual(selected.value, 0); XCTAssertEqual(ruler.value, 0)
        XCTAssertTrue(tools.setQuickColor(.purple, at: 0))
        XCTAssertEqual(favorites.value, 1); XCTAssertEqual(nextInk.value, 0)
        tools.selected = .pencil
        let defaultPencilWidth = tools.ink.width
        XCTAssertEqual(selected.value, 1); XCTAssertEqual(nextInk.value, 1)
        tools.rulerEnabled = true; XCTAssertEqual(ruler.value, 1)
        tools.ink.width = 3.5; tools.resetCurrentTool()
        XCTAssertEqual(tools.ink.width, defaultPencilWidth)
        tools.selected = .pen; XCTAssertEqual(tools.ink.width, 4.5)
    }

    func testUnchangedOverlayStateDoesNotRequestRedrawButSelectionAndZoomDo() {
        let overlay = PageObjectsInteractionView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        overlay.layer.displayIfNeeded()
        XCTAssertFalse(overlay.layer.needsDisplay())
        overlay.selectedID = nil; overlay.revealed = []; overlay.tool = .pen; overlay.zoom = 1
        XCTAssertFalse(overlay.layer.needsDisplay())
        overlay.tool = .objects
        XCTAssertTrue(overlay.layer.needsDisplay())
        overlay.layer.displayIfNeeded()
        overlay.zoom = 2; XCTAssertTrue(overlay.layer.needsDisplay())
        overlay.layer.displayIfNeeded()
        overlay.tool = .pen; XCTAssertTrue(overlay.layer.needsDisplay(), "Leaving selection must remove its outline.")
    }

    func testTextLayoutReuseMatchesUncachedPixelsAndInvalidatesRelevantEdits() throws {
        let cache = PageTextLayoutCache()
        var item = PageElement(kind: .text, rect: CGRect(x: 20, y: 40, width: 350, height: 100))
        item.text = "Biología celular: write, study, remember."
        item.fontName = HandwritingFont.defaultName
        _ = cache.frame(for: item)
        for _ in 0..<20 { item.x += 0.5; item.y += 0.25; _ = cache.frame(for: item) }
        XCTAssertEqual(cache.builds, 1); XCTAssertEqual(cache.hits, 20)
        let cached = try XCTUnwrap(render([item], cache: cache).pngData())
        let uncached = try XCTUnwrap(render([item], cache: nil).pngData())
        XCTAssertEqual(cached, uncached)
        item.width = 200; _ = cache.frame(for: item)
        item.fontSize = 30; _ = cache.frame(for: item)
        item.text += " Changed."; _ = cache.frame(for: item)
        item.red = 0.8; _ = cache.frame(for: item)
        XCTAssertEqual(cache.builds, 5)
        item.originalInk = Data([1, 2, 3]); _ = cache.frame(for: item)
        XCTAssertEqual(cache.builds, 5, "Recovery bytes do not affect text layout.")
    }

    func testRepeatedTextRefreshWorkload() {
        let items = (0..<12).map { index in
            var item = PageElement(kind: .text, rect: CGRect(x: 20, y: 20 + index * 52, width: 420, height: 48))
            item.text = "Lecture \(index): cells, membranes and organelles."
            item.fontSize = 20
            return item
        }
        _ = render(items, cache: nil) // Warm system font resources outside the timed region.
        let clock = ContinuousClock(), cache = PageTextLayoutCache()
        let start = clock.now
        for _ in 0..<20 { autoreleasepool { _ = render(items, cache: nil) } }
        let uncached = start.duration(to: clock.now)
        let cachedStart = clock.now
        for _ in 0..<20 { autoreleasepool { _ = render(items, cache: cache) } }
        let cached = cachedStart.duration(to: clock.now)
        XCTAssertEqual(cache.builds, 12); XCTAssertEqual(cache.hits, 228)
        let result = "20 refreshes × 12 text objects. Uncached: \(ms(uncached)) ms; cached: \(ms(cached)) ms. Layout builds: 240 → 12. Simulator sample, not hardware FPS."
        print("FLUIDITY \(result)")
        add(XCTAttachment(string: result))
    }

    func testBackgroundContentDecodeImagesAndCancellationPreserveErrors() async throws {
        var item = PageElement(kind: .text, rect: CGRect(x: 20, y: 20, width: 200, height: 100))
        item.text = "Retain editable source"
        item.originalInk = Data(repeating: 42, count: 50_000)
        let encoded = try PageElementsCodec.encode([item])
        let decoded = try await PageLoader.elements(encoded)
        XCTAssertEqual(decoded, [item])
        let cancelled = Task { try await PageLoader.elements(encoded) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled decoding must not publish content.") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do { _ = try await PageLoader.elements(Data([0, 1, 2])); XCTFail("Corrupt metadata must remain an error.") }
        catch {}
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        try await storage.write(XCTUnwrap(image.pngData()), to: "image.png")
        var photo = PageElement(kind: .image, rect: CGRect(x: 0, y: 0, width: 200, height: 100))
        photo.imagePath = "image.png"
        let loaded = try await PageImageService.load([photo], storage: storage)
        XCTAssertEqual(loaded["image.png"]?.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(loaded["image.png"]?.cgImage?.height, image.cgImage?.height)
        try await storage.write(Data([0, 1, 2]), to: "image.png")
        do { _ = try await PageImageService.load([photo], storage: storage); XCTFail("Corrupt image must remain an error.") }
        catch {}
    }

    private func render(_ items: [PageElement], cache: PageTextLayoutCache?) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 700), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 700))
            PageElementRenderer.draw(items, images: [:], textLayouts: cache, in: context.cgContext)
        }
    }
    private func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
