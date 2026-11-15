import XCTest
import SwiftUI
import SwiftData
import PencilKit
import PDFKit
@testable import NotesApp

@MainActor final class ExpandedStudentToolTests: XCTestCase {
    private func stroke(_ type: PKInkingTool.InkType = .pen, y: CGFloat = 80, transform: CGAffineTransform = .identity) -> PKStroke {
        let points = (0...20).map { PKStrokePoint(location: CGPoint(x: 40 + $0 * 4, y: Int(y)), timeOffset: Double($0) * 0.02,
            size: CGSize(width: type == .marker ? 16 : 3, height: type == .marker ? 16 : 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2) }
        return PKStroke(ink: PKInk(type, color: type == .marker ? .yellow : .blue), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1)), transform: transform)
    }
    func testSelectiveEraserPreservesPenAndDistantMarkerIncludingTransforms() async throws {
        let pen = stroke(), marker = stroke(.marker), distant = stroke(.marker, y: 250)
        let shifted = stroke(.marker, transform: CGAffineTransform(translationX: 200, y: 0))
        let drawing = PKDrawing(strokes: [pen, marker, distant, shifted])
        let erased = SelectiveInkEraser.eraseHighlighter(drawing, along: [CGPoint(x: 80, y: 60), CGPoint(x: 80, y: 100)], radius: 6)
        XCTAssertEqual(erased.strokes.count, 3)
        XCTAssertTrue(StrokeContent.matches([erased.strokes[0]], [pen]))
        XCTAssertTrue(StrokeContent.matches(Array(erased.strokes.dropFirst()), [distant, shifted]))
        let second = SelectiveInkEraser.eraseHighlighter(erased, along: [CGPoint(x: 280, y: 80)], radius: 6)
        XCTAssertEqual(second.strokes.count, 2)
        XCTAssertEqual(SelectiveInkEraser.eraseHighlighter(drawing, along: [], radius: 5), drawing)
    }
    func testSelectiveEraserRespectsMaskedAndScaledMarkerStrokes() {
        let base = stroke(.marker)
        let masked = PKStroke(ink: base.ink, path: base.path, transform: .identity,
                              mask: UIBezierPath(rect: CGRect(x: 38, y: 65, width: 25, height: 30)))
        let drawing = PKDrawing(strokes: [masked])
        let hidden = SelectiveInkEraser.eraseHighlighter(drawing, along: [CGPoint(x: 110, y: 80)], radius: 3)
        XCTAssertEqual(hidden.strokes.count, 1)
        let visible = SelectiveInkEraser.eraseHighlighter(drawing, along: [CGPoint(x: 50, y: 80)], radius: 3)
        XCTAssertTrue(visible.strokes.isEmpty)
        let scaled = stroke(.marker, transform: CGAffineTransform(scaleX: 3, y: 3))
        let erased = SelectiveInkEraser.eraseHighlighter(PKDrawing(strokes: [scaled]), along: [CGPoint(x: 240, y: 259)], radius: 2)
        XCTAssertTrue(erased.strokes.isEmpty)
    }

    func testSelectiveEraserHasUndoAndPersistsOnlyReplacement() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        let original = PKDrawing(strokes: [stroke(), stroke(.marker)])
        f.canvas.drawing = original; f.session.changed(original)
        await f.session.eraseHighlighter(along: [CGPoint(x: 80, y: 80)], radius: 8)
        XCTAssertEqual(f.session.drawing.strokes.count, 1)
        f.canvas.undoManager?.undo(); XCTAssertEqual(f.session.drawing, original)
        f.canvas.undoManager?.redo(); XCTAssertEqual(f.session.drawing.strokes.count, 1)
        let saved = await f.session.flush(); XCTAssertTrue(saved)
        let bytes = try await f.storage.read(try XCTUnwrap(f.page.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: bytes), f.session.drawing)
    }
    func testShapeSnapCombinesInkAndObjectsUndoAndRetainsOriginalInk() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        let existing = PKDrawing(strokes: [stroke(y: 240)]), source = PKDrawing(strokes: [stroke()])
        let full = PKDrawing(strokes: existing.strokes + source.strokes)
        f.canvas.drawing = full; f.session.changed(full)
        let match = SmartShapeMatch(kind: .line, rect: CGRect(x: 40, y: 80, width: 80, height: 1), reversed: false)
        let applied = await f.session.applySmartShape(match, before: existing, snapshot: full, pageID: f.page.id, style: InkStyle())
        XCTAssertTrue(applied); XCTAssertEqual(f.session.drawing, existing)
        let element = try XCTUnwrap(f.session.elements.first)
        XCTAssertTrue(try StrokeContent.matches(PKDrawing(data: XCTUnwrap(element.originalInk)).strokes, source.strokes))
        f.canvas.undoManager?.undo(); XCTAssertEqual(f.session.drawing, full); XCTAssertTrue(f.session.elements.isEmpty)
        f.canvas.undoManager?.redo(); XCTAssertEqual(f.session.elements.first?.id, element.id)
        XCTAssertTrue(f.session.restoreOriginalInk(element.id)); XCTAssertEqual(f.session.drawing.strokes.count, 2)
        XCTAssertTrue(f.session.elements.isEmpty)
    }
    func testShapeSnapRejectsStalePageWithoutDroppingInk() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        let full = PKDrawing(strokes: [stroke()]); f.canvas.drawing = full; f.session.changed(full)
        let applied = await f.session.applySmartShape(.init(kind: .line, rect: CGRect(x: 40, y: 80, width: 80, height: 1), reversed: false), before: PKDrawing(), snapshot: full, pageID: UUID(), style: InkStyle())
        XCTAssertFalse(applied); XCTAssertEqual(f.session.drawing, full); XCTAssertTrue(f.session.elements.isEmpty)
    }
    func testStampsAndFoldedNotesSurviveReopenAndExport() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        f.session.insertStamp(at: CGPoint(x: 80, y: 80), symbol: .check, style: InkStyle())
        f.session.requestSticky(at: CGPoint(x: 200, y: 180), style: .rose)
        var note = try XCTUnwrap(f.session.requestedNote); note.text = "Remember ATP"; f.session.requestedNote = nil
        XCTAssertTrue(f.session.insertElement(note)); f.session.toggleSticky(note.id)
        await f.session.open(f.page)
        XCTAssertEqual(f.session.elements.first?.text, StampSymbol.check.rawValue)
        XCTAssertEqual(f.session.elements.last?.folded, true); XCTAssertEqual(f.session.elements.last?.text, note.text)
        let exported = await f.session.export(currentPageOnly: true)
        let url = try XCTUnwrap(exported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 1)
    }
    func testPDFTextSelectionMatchesRotatedCroppedPageAndLeavesOriginalUnchanged() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { ctx in
            ctx.beginPage(); ("Mitochondria produce ATP" as NSString).draw(at: CGPoint(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        let document = try XCTUnwrap(PDFDocument(data: data)), page = try XCTUnwrap(document.page(at: 0))
        page.setBounds(CGRect(x: 20, y: 30, width: 350, height: 540), for: .cropBox); page.rotation = 90
        let original = try XCTUnwrap(document.dataRepresentation()); try await f.storage.write(original, to: "Sources/test.pdf")
        let storedPage = try XCTUnwrap(PDFDocument(data: original)?.page(at: 0))
        let size = try PDFRendering.size(of: storedPage)
        let selected = try await PDFDocumentService.shared.selectText(path: "Sources/test.pdf", index: 0, region: CGRect(origin: .zero, size: size), storage: f.storage)
        XCTAssertTrue(selected.text.contains("Mitochondria")); XCTAssertFalse(selected.lines.isEmpty)
        for rect in selected.lines { XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect)) }
        let line = try XCTUnwrap(selected.lines.first)
        let precise = try await PDFDocumentService.shared.selectText(path: "Sources/test.pdf", index: 0, region: line.insetBy(dx: -2, dy: -2), storage: f.storage)
        XCTAssertTrue(precise.text.contains("Mitochondria"))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { PDFRendering.draw(storedPage, size: size, in: $0.cgContext) }
        let cg = try XCTUnwrap(rendered.cgImage)
        var pixels = [UInt8](repeating: 255, count: cg.width * cg.height * 4)
        let raster = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        raster.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var dark = 0, inside = 0; var inkBounds = CGRect.null
        for y in 0..<cg.height { for x in 0..<cg.width {
            let i = (y * cg.width + x) * 4
            if pixels[i] < 100 && pixels[i + 1] < 100 && pixels[i + 2] < 100 {
                dark += 1; inkBounds = inkBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                if selected.lines.contains(where: { $0.insetBy(dx: -3, dy: -3).contains(CGPoint(x: x, y: y)) }) { inside += 1 }
            }
        } }
        XCTAssertGreaterThan(dark, 100); XCTAssertGreaterThan(Double(inside) / Double(max(1, dark)), 0.9, "Selection \(selected.lines); raster ink \(inkBounds)")
        let marked = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            rendered.draw(at: .zero); ctx.cgContext.setFillColor(UIColor.yellow.withAlphaComponent(0.4).cgColor)
            for rect in selected.lines { ctx.cgContext.fill(rect) }
        }
        let attachment = XCTAttachment(image: marked); attachment.name = "Rotated-PDF-Text-Highlight"; attachment.lifetime = .keepAlways; add(attachment)
        let retained = try await f.storage.read("Sources/test.pdf"); XCTAssertEqual(retained, original)
    }
    func testPDFHighlightIsUndoableAndMarginSelectionDoesNotInventText() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { ctx in
            ctx.beginPage(); ("ATP synthesis" as NSString).draw(at: CGPoint(x: 50, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        try await f.storage.write(data, to: "Sources/text.pdf")
        f.page.pdfFilePath = "Sources/text.pdf"; f.page.pdfPageIndex = 0; f.page.pageWidth = 400; f.page.pageHeight = 600; f.page.pdfRightMargin = 200
        try f.container.mainContext.save(); await f.open()
        await f.session.highlightPDF(CGRect(x: 0, y: 0, width: 400, height: 600), expectedPageID: f.page.id)
        XCTAssertFalse(f.session.elements.isEmpty); XCTAssertTrue(f.session.elements.allSatisfy { $0.filled == true })
        f.canvas.undoManager?.undo(); XCTAssertTrue(f.session.elements.isEmpty)
        await f.session.highlightPDF(CGRect(x: 420, y: 0, width: 150, height: 600), expectedPageID: f.page.id)
        XCTAssertTrue(f.session.elements.isEmpty); XCTAssertNotNil(f.session.errorMessage)
        let unchanged = try await f.storage.read("Sources/text.pdf"); XCTAssertEqual(unchanged, data)
    }
    func testPageCaptureCropsPixelRegionsAndStoresRealLinkedImageCards() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        var box = PageElement(kind: .rectangle, rect: CGRect(x: 0, y: 0, width: 768, height: 543)); box.filled = true; box.red = 1; box.green = 0; box.blue = 0
        XCTAssertTrue(f.session.insertElement(box))
        f.canvas.drawing = PKDrawing(strokes: [stroke(y: 700)]) // Flush must read pending native ink.
        let captured = await f.session.capturePage(expectedPageID: f.page.id)
        let snapshot = try XCTUnwrap(captured)
        XCTAssertEqual(snapshot.source.pageID, f.page.id); XCTAssertEqual(f.session.drawing.strokes.count, 1)
        let images = try await StudyCaptureImages.shared.store(snapshot: snapshot, question: CGRect(x: 0, y: 0, width: 1, height: 0.5), answer: CGRect(x: 0, y: 0.5, width: 1, height: 0.5), storage: f.storage)
        let question = try await f.storage.read(try XCTUnwrap(images.question)), answer = try await f.storage.read(try XCTUnwrap(images.answer))
        XCTAssertNotEqual(question, answer)
        XCTAssertEqual(UIImage(data: question)?.cgImage?.height, 1024)
        let study = StudyViewModel(container: f.container), deck = try study.saveDeck(title: "Biology", notebookID: f.book.id)
        let card = try study.saveCard(deckID: deck.id, question: "Question region", answer: "Answer region", source: snapshot.source, images: images)
        try study.review(card.id, rating: .good, at: .now)
        _ = try study.saveCard(id: card.id, deckID: deck.id, question: "Updated description", answer: "Answer region", source: snapshot.source)
        let reopened = ModelContext(f.container), saved = try XCTUnwrap(reopened.fetch(FetchDescriptor<Flashcard>()).first)
        XCTAssertEqual(saved.questionImagePath, images.question); XCTAssertEqual(saved.answerImagePath, images.answer)
        XCTAssertEqual(saved.sourcePageID, f.page.id); XCTAssertEqual(saved.reviews.count, 1)
        do { _ = try await PageCaptureService.shared.crop(snapshot.png, normalized: CGRect(x: 2, y: 2, width: 1, height: 1)); XCTFail("Outside crop must fail") } catch {}
    }
    func testZoomFlushUsesSecondaryCanvasBeforeDelegateAndHistorySurvivesClosing() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        let before = PKDrawing(strokes: [stroke()]); f.canvas.drawing = before; f.session.changed(before)
        f.session.beginZoomWriting(CGRect(x: 40, y: 100, width: 300, height: 100))
        let zoom = InkCanvas(); zoom.pageID = f.page.id; zoom.drawing = PKDrawing(strokes: [stroke(), stroke(y: 140)])
        f.session.zoomCanvas = zoom
        let closed = await f.session.closeZoomWriting(); XCTAssertTrue(closed)
        XCTAssertEqual(f.session.drawing, zoom.drawing); XCTAssertEqual(f.canvas.drawing, zoom.drawing)
        XCTAssertNil(f.session.writingRegion); XCTAssertNil(f.session.zoomCanvas)
        let bytes = try await f.storage.read(try XCTUnwrap(f.page.drawingFilePath)); XCTAssertEqual(try PKDrawing(data: bytes), zoom.drawing)
        f.canvas.undoManager?.undo(); XCTAssertEqual(f.session.drawing, before)
        f.canvas.undoManager?.redo(); XCTAssertEqual(f.session.drawing, zoom.drawing)
    }
    func testClearInkInZoomSynchronizesOverviewAndUsesWindowUndo() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        let original = PKDrawing(strokes: [stroke()]); f.canvas.drawing = original; f.session.changed(original)
        f.session.beginZoomWriting(CGRect(x: 40, y: 100, width: 300, height: 100))
        let zoom = InkCanvas(); zoom.pageID = f.page.id; zoom.drawing = original; f.session.zoomCanvas = zoom
        f.session.clearHandwriting()
        XCTAssertTrue(zoom.drawing.strokes.isEmpty && f.canvas.drawing.strokes.isEmpty && f.session.drawing.strokes.isEmpty)
        zoom.undoManager?.undo(); XCTAssertEqual(f.session.drawing, original); XCTAssertEqual(f.canvas.drawing, original)
        zoom.undoManager?.redo(); XCTAssertTrue(f.session.drawing.strokes.isEmpty)
        let saved = await f.session.flush(); XCTAssertTrue(saved)
        let bytes = try await f.storage.read(try XCTUnwrap(f.page.drawingFilePath)); XCTAssertTrue(try PKDrawing(data: bytes).strokes.isEmpty)
    }

    func testZoomPageSwitchSavesCorrectPageAndFailureRetainsWindowAndInk() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        f.session.beginZoomWriting(CGRect(x: 40, y: 100, width: 300, height: 100))
        let zoom = InkCanvas(); zoom.pageID = f.page.id; zoom.drawing = PKDrawing(strokes: [stroke()]); f.session.zoomCanvas = zoom
        await f.session.open(f.second)
        XCTAssertEqual(f.session.page?.id, f.second.id); XCTAssertTrue(f.session.drawing.strokes.isEmpty); XCTAssertNil(f.session.writingRegion)
        let bytes = try await f.storage.read(try XCTUnwrap(f.page.drawingFilePath)); XCTAssertEqual(try PKDrawing(data: bytes), zoom.drawing)
        let blocked = try ExpandedToolFixture(blocked: true); defer { blocked.cleanup() }; await blocked.open()
        blocked.session.beginZoomWriting(CGRect(x: 40, y: 100, width: 300, height: 100))
        let unsaved = InkCanvas(); unsaved.pageID = blocked.page.id; unsaved.drawing = zoom.drawing; blocked.session.zoomCanvas = unsaved
        let closed = await blocked.session.closeZoomWriting(); XCTAssertFalse(closed)
        XCTAssertNotNil(blocked.session.writingRegion); XCTAssertTrue(blocked.session.zoomCanvas === unsaved)
        XCTAssertEqual(blocked.session.drawing, unsaved.drawing); XCTAssertTrue(blocked.session.hasPendingSave)
    }
    func testAuxiliaryPresetsAndLaserStylePersistWithoutOverwritingPen() throws {
        let suite = "ExpandedTools.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let tools = ToolPreferences(defaults: defaults); tools.ink.width = 4; tools.smartShapes = true
        tools.selected = .laser; tools.ink = InkStyle(red: 1, green: 0, blue: 0, width: 6)
        tools.selected = .stamp; tools.stampSymbol = .star
        let preset = tools.capturePreset(name: "Important")
        tools.stampSymbol = .cross; tools.apply(preset)
        XCTAssertEqual(tools.stampSymbol, .star)
        let reopened = ToolPreferences(defaults: defaults); XCTAssertTrue(reopened.smartShapes)
        XCTAssertEqual(reopened.inkStyle(for: .pen).width, 4); XCTAssertEqual(reopened.inkStyle(for: .laser).width, 6)
        XCTAssertNotNil(UIImage(systemName: EditorTool.laser.symbol))
        // Native visual QA attachments for the laser style; this adds no simulated Pencil input.
        for (name, paper, color) in [("White", UIColor.white, UIColor.systemRed), ("Dark", UIColor(white: 0.12, alpha: 1), UIColor.systemRed), ("Blue", UIColor.white, UIColor.systemBlue)] {
            let preview = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 240)); preview.backgroundColor = paper
            let light = LaserPointerVisual(); light.layer.frame = preview.bounds
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            light.style = InkStyle(red: r, green: g, blue: b, width: 3)
            preview.layer.addSublayer(light.layer)
            light.show([CGPoint(x: 65, y: 150), CGPoint(x: 130, y: 135), CGPoint(x: 190, y: 145), CGPoint(x: 250, y: 105), CGPoint(x: 330, y: 115), CGPoint(x: 430, y: 85), CGPoint(x: 510, y: 90)])
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: preview.bounds.size, format: format).image { preview.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image); attachment.name = "Laser-Light-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            light.clear()
        }
    }
    func testRegionCardFormAndImageReviewRenderRealCaptures() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        f.session.insertStamp(at: CGPoint(x: 200, y: 180), symbol: .star, style: InkStyle())
        let captured = await f.session.capturePage(expectedPageID: f.page.id)
        let snapshot = try XCTUnwrap(captured)
        let images = try await StudyCaptureImages.shared.store(snapshot: snapshot, question: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3), answer: CGRect(x: 0, y: 0, width: 1, height: 0.5), storage: f.storage)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        defer { window.isHidden = true; window.rootViewController = nil }
        let form = UIHostingController(rootView: RegionFlashcardForm(snapshot: snapshot, initialRegion: CGRect(x: 80, y: 80, width: 380, height: 300), container: f.container, storage: f.storage))
        window.rootViewController = form; window.isHidden = false; form.view.frame = window.bounds; form.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        var image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        var attachment = XCTAttachment(image: image); attachment.name = "Region-Flashcard-Form"; attachment.lifetime = .keepAlways; add(attachment)
        let review = UIHostingController(rootView: StudyReviewCard(question: "Important concept", answer: "Answer from notes", questionImagePath: images.question, answerImagePath: images.answer, storage: f.storage, isAnswerVisible: false, flip: {}).padding(40))
        window.rootViewController = review; review.view.frame = window.bounds; review.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200)); review.view.layoutIfNeeded()
        image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        attachment = XCTAttachment(image: image); attachment.name = "Region-Flashcard-Review"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(review.view.bounds.height, 0)
    }

    func testZoomWindowRendersWithPageOverviewInPortraitAndLandscape() async throws {
        let f = try ExpandedToolFixture(); defer { f.cleanup() }; await f.open()
        f.session.insertStamp(at: CGPoint(x: 220, y: 200), symbol: .star, style: InkStyle())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let suite = "ExpandedLayout.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        for size in [CGSize(width: 1180, height: 820), CGSize(width: 820, height: 1180)] {
            f.session.beginZoomWriting(CGRect(x: 60, y: 150, width: 320, height: 130))
            window.frame = CGRect(origin: .zero, size: size)
            let host = UIHostingController(rootView: EditorView(session: f.session, onLibrary: {}, preferencesDefaults: defaults, showsWorkspaceTabs: false))
            window.rootViewController = host; window.isHidden = false; host.view.frame = window.bounds
            host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200)); host.view.layoutIfNeeded()
            XCTAssertNotNil(f.session.zoomCanvas); XCTAssertGreaterThan(try XCTUnwrap(f.session.zoomCanvas?.window).bounds.width, 0)
            let image = UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Expanded-Zoom-\(Int(size.width))"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
            _ = await f.session.closeZoomWriting()
        }
    }
}

@MainActor private final class ExpandedToolFixture {
    // SwiftUI releases hosted views asynchronously; keep their in-memory stores alive for the runner.
    private static var liveContainers: [ModelContainer] = []
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let container: ModelContainer
    let storage: DrawingStorage
    let book = Notebook(title: "Biology")
    let page = NotePage(pageIndex: 0), second = NotePage(pageIndex: 1)
    let canvas = InkCanvas()
    let session: EditorSession
    init(blocked: Bool = false) throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        Self.liveContainers.append(container)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let documents = root.appendingPathComponent("Documents")
        if blocked { try Data([1]).write(to: documents) }
        storage = DrawingStorage(root: documents)
        container.mainContext.insert(book); container.mainContext.insert(page); container.mainContext.insert(second); book.pages = [page, second]
        try container.mainContext.save()
        let defaults = UserDefaults(suiteName: "ExpandedAssistant.\(UUID())")!
        session = EditorSession(notebook: book, context: container.mainContext, storage: storage, handwriting: HandwritingAssistant(defaults: defaults))
    }
    func open() async { await session.open(page); canvas.pageID = page.id; session.canvas = canvas }
    func cleanup() { session.canvas?.undoManager?.removeAllActions(); session.discardPreparedPages(); try? FileManager.default.removeItem(at: root) }
}
