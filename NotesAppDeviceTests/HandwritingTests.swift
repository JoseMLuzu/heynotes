import XCTest
import SwiftData
import SwiftUI
import PencilKit
import PDFKit
@testable import NotesApp

private actor ImmediateHandwritingRecognizer: HandwritingRecognizing {
    let text: String?
    private(set) var calls = 0
    init(_ text: String?) { self.text = text }
    func recognize(_ drawing: PKDrawing, language: String) async throws -> String? { calls += 1; return text }
}

private actor HeldHandwritingRecognizer: HandwritingRecognizing {
    private var continuation: CheckedContinuation<String?, Never>?
    var started: Bool { continuation != nil }
    func recognize(_ drawing: PKDrawing, language: String) async throws -> String? {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: "Hello"); continuation = nil }
}

@MainActor final class HandwritingTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private func stroke(_ points: [CGPoint]) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points.enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.02,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSince1970: 1)))
    }
    private func ink(_ x: CGFloat = 60) -> PKDrawing {
        PKDrawing(strokes: [stroke([CGPoint(x: x, y: 100), CGPoint(x: x + 40, y: 150)])])
    }
    private func fixture(_ root: URL, recognizer: (any HandwritingRecognizing)? = nil) async throws -> EditorSession {
        let container = try PersistenceController.makeContainer(inMemory: true)
        containers.append(container)
        let notebook = Notebook(title: "Handwriting"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        try container.mainContext.save()
        let suite = UserDefaults(suiteName: "handwriting.tests.\(UUID())")!
        let assistant = HandwritingAssistant(defaults: suite, recognizer: recognizer ?? VisionHandwritingRecognizer.shared)
        let session = EditorSession(notebook: notebook, context: container.mainContext,
                                    storage: DrawingStorage(root: root), handwriting: assistant)
        await session.open(page)
        let canvas = InkCanvas(); canvas.pageID = page.id
        session.canvas = canvas
        return session
    }
    private func put(_ drawing: PKDrawing, in session: EditorSession) {
        session.canvas?.drawing = drawing; session.changed(drawing)
    }
    private func assertInk(_ actual: PKDrawing, _ expected: PKDrawing, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.strokes.count, expected.strokes.count, file: file, line: line)
        XCTAssertEqual(actual.bounds, expected.bounds, file: file, line: line)
        XCTAssertEqual(actual.strokes.map { $0.path.map(\.location) }, expected.strokes.map { $0.path.map(\.location) }, file: file, line: line)
        XCTAssertEqual(actual.strokes.map(\.transform), expected.strokes.map(\.transform), file: file, line: line)
        XCTAssertEqual(actual.strokes.map(\.ink.color), expected.strokes.map(\.ink.color), file: file, line: line)
    }

    func testOCRRasterRetainsDarkInkUnderDarkAppearance() throws {
        let drawing = ink()
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            image = VisionHandwritingRecognizer.raster(drawing)?.0
        }
        let cg = try XCTUnwrap(image?.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
                                            bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let darkPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 80 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 && pixels[$0 + 3] > 240
        }.count
        XCTAssertGreaterThan(darkPixels, 100, "OCR must receive visible dark ink even when the app uses Dark Mode.")
        XCTAssertEqual(pixels[0], 255); XCTAssertEqual(pixels[1], 255); XCTAssertEqual(pixels[2], 255)
    }

    func testConversionUndoRedoReopenAndOriginalRecovery() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await fixture(root), page = try XCTUnwrap(session.page)
        let original = ink(); put(original, in: session)
        let converted = await session.applyRecognizedHandwriting("Hello world", source: original, snapshot: original,
                                                                pageID: page.id, fontName: HandwritingFont.defaultName)
        XCTAssertTrue(converted)
        let item = try XCTUnwrap(session.elements.first)
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(item.originalInk)), original)
        XCTAssertTrue(session.drawing.strokes.isEmpty)
        let archive = try await session.storage.read("Notebooks/\(session.notebook.id)/Handwriting/\(item.id).drawing")
        XCTAssertEqual(try PKDrawing(data: archive), original)
        session.canvas?.undoManager?.undo()
        XCTAssertEqual(session.drawing, original); XCTAssertTrue(session.elements.isEmpty)
        session.canvas?.undoManager?.redo()
        XCTAssertTrue(session.drawing.strokes.isEmpty); XCTAssertEqual(session.elements, [item])
        let saved = await session.flush(); XCTAssertTrue(saved)
        await session.open(page)
        XCTAssertEqual(session.elements.first?.fontName, item.fontName)
        XCTAssertTrue(session.drawing.strokes.isEmpty)
        XCTAssertTrue(session.restoreOriginalInk(item.id))
        XCTAssertTrue(session.elements.isEmpty); assertInk(session.drawing, original)
        let restored = await session.flush(); XCTAssertTrue(restored)
        let restoredData = try await session.storage.read(XCTUnwrap(page.drawingFilePath))
        assertInk(try PKDrawing(data: restoredData), original)
        // The immutable recovery archive survives Undo and restoring/removing the text object.
        let retained = try await session.storage.read("Notebooks/\(session.notebook.id)/Handwriting/\(item.id).drawing")
        XCTAssertEqual(try PKDrawing(data: retained), original)
    }

    func testStaleOrNonSuffixRecognitionCannotRemoveInk() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await fixture(root), pageID = try XCTUnwrap(session.page?.id)
        let original = ink(), newer = PKDrawing(strokes: original.strokes + ink(160).strokes)
        put(newer, in: session)
        let stale = await session.applyRecognizedHandwriting("Hello", source: original, snapshot: original, pageID: pageID, fontName: HandwritingFont.defaultName)
        XCTAssertFalse(stale)
        let wrongSuffix = await session.applyRecognizedHandwriting("Hello", source: original, snapshot: newer, pageID: pageID, fontName: HandwritingFont.defaultName)
        XCTAssertFalse(wrongSuffix)
        let cancelled = await session.applyRecognizedHandwriting("Hello", source: newer, snapshot: newer, pageID: pageID, fontName: HandwritingFont.defaultName, isCurrent: { false })
        XCTAssertFalse(cancelled)
        XCTAssertEqual(session.drawing, newer); XCTAssertTrue(session.elements.isEmpty)
    }

    func testPausedConversionOnlyConsumesNewInkAndSkipsHighlighter() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recognizer = ImmediateHandwritingRecognizer("Hello")
        let session = try await fixture(root, recognizer: recognizer)
        let old = ink(); put(old, in: session)
        session.handwriting.setEnabled(true, session: session)
        let phrase = ink(160)
        let newer = PKDrawing(strokes: old.strokes + phrase.strokes)
        put(newer, in: session)
        for _ in 0..<150 {
            if !session.elements.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.elements.count, 1)
        assertInk(session.drawing, old)
        assertInk(try PKDrawing(data: XCTUnwrap(session.elements.first?.originalInk)), phrase)
        session.handwriting.setTool(.marker, session: session)
        let highlighted = PKDrawing(strokes: old.strokes + ink(260).strokes)
        put(highlighted, in: session)
        try await Task.sleep(for: .milliseconds(1_350))
        let calls = await recognizer.calls
        XCTAssertEqual(calls, 1); XCTAssertEqual(session.drawing, highlighted)
        session.handwriting.setEnabled(false, session: session)
        let saved = await session.flush(); XCTAssertTrue(saved)
    }

    func testPendingRecognitionIsDiscardedAfterPageChange() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recognizer = HeldHandwritingRecognizer()
        let session = try await fixture(root, recognizer: recognizer)
        let originalPage = try XCTUnwrap(session.page), original = ink(); put(original, in: session)
        let conversion = Task { await session.handwriting.convertPage(session: session) }
        for _ in 0..<100 { if await recognizer.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        let started = await recognizer.started; XCTAssertTrue(started)
        let next = NotePage(pageIndex: 1)
        session.context.insert(next); session.notebook.pages.append(next)
        await session.open(next)
        await recognizer.finish(); await conversion.value
        XCTAssertEqual(session.page?.id, next.id); XCTAssertTrue(session.elements.isEmpty)
        XCTAssertTrue(try PageElementsCodec.decode(originalPage.objectsData).isEmpty)
        let preserved = try await session.storage.read(XCTUnwrap(originalPage.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: preserved), original)
    }

    func testUnrecognizedPhraseKeepsInk() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await fixture(root, recognizer: ImmediateHandwritingRecognizer(nil))
        let original = ink(); put(original, in: session)
        await session.handwriting.convertPage(session: session)
        XCTAssertTrue(session.elements.isEmpty); XCTAssertEqual(session.drawing, original)
        XCTAssertTrue(session.handwriting.message.contains("Original ink was kept"))
        let saved = await session.flush(); XCTAssertTrue(saved)
    }

    func testRealVisionRecognizesPencilKitBlockLetters() async throws {
        // A deterministic, hand-constructed stroke fixture exercises the real raster/Vision pipeline.
        var paths: [[CGPoint]] = []
        func line(_ values: [(CGFloat, CGFloat)]) { paths.append(values.map { CGPoint(x: $0.0, y: $0.1) }) }
        line([(50, 100), (50, 170)]); line([(90, 100), (90, 170)]); line([(50, 135), (90, 135)])
        line([(150, 100), (110, 100), (110, 170), (150, 170)]); line([(110, 135), (145, 135)])
        line([(170, 100), (170, 170), (210, 170)])
        line([(230, 100), (230, 170), (270, 170)])
        paths.append((0...40).map { i in
            let angle = Double(i) / 40 * 2 * .pi
            return CGPoint(x: 310 + 22 * cos(angle), y: 135 + 35 * sin(angle))
        })
        let drawing = PKDrawing(strokes: paths.map(stroke))
        let raster = try XCTUnwrap(VisionHandwritingRecognizer.raster(drawing)?.0)
        let attachment = XCTAttachment(image: raster); attachment.name = "Handwriting-OCR-Input"; attachment.lifetime = .keepAlways; add(attachment)
        let result = try await VisionHandwritingRecognizer.shared.recognize(drawing, language: "en-US")
        XCTAssertEqual(result?.uppercased().replacingOccurrences(of: " ", with: ""), "HELLO")
        let blank = try await VisionHandwritingRecognizer.shared.recognize(PKDrawing(), language: "en-US")
        XCTAssertNil(blank)
    }

    func testFontsExportAndConfigurationAppearance() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await fixture(root)
        XCTAssertGreaterThanOrEqual(HandwritingFont.choices.count, 2)
        var items: [PageElement] = []
        for (index, choice) in HandwritingFont.choices.enumerated() {
            var item = PageElement(kind: .text, rect: CGRect(x: 40, y: 60 + index * 100, width: 600, height: 80))
            item.fontName = choice.name; item.fontSize = 30; item.text = "\(choice.title): Write. Study. Remember."
            XCTAssertEqual(HandwritingFont.resolve(choice.name, size: 30).fontName, choice.name)
            items.append(item)
        }
        XCTAssertTrue(session.replaceElements(items))
        let exported = await session.export(currentPageOnly: true)
        let url = try XCTUnwrap(exported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        let pdf = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(pdf.bounds(for: .mediaBox).size, session.page?.logicalSize)
        for choice in HandwritingFont.choices { XCTAssertTrue(pdf.string?.contains(choice.title) == true) }
        let preview = XCTAttachment(image: pdf.thumbnail(of: CGSize(width: 768, height: 1086), for: .mediaBox))
        preview.name = "Handwriting-Fonts-PDF"; preview.lifetime = .keepAlways; add(preview)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 760, height: 960)
        let host = UIHostingController(rootView: HandwritingStyleView(session: session))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Handwriting-Style-Settings"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
