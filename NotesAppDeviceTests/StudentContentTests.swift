import XCTest
import PDFKit
import PencilKit
import SwiftData
import SwiftUI
@testable import NotesApp

@MainActor final class StudentContentTests: XCTestCase {
    func testInsertedContentUndoTapeRevealAndReopening() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Study"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let canvas = InkCanvas(); canvas.pageID = page.id; session.canvas = canvas
        var text = PageElement(kind: .text, rect: CGRect(x: 40, y: 40, width: 240, height: 100)); text.text = "Mitochondria"
        XCTAssertTrue(session.insertElement(text))
        canvas.undoManager?.undo(); XCTAssertTrue(session.elements.isEmpty)
        canvas.undoManager?.redo(); XCTAssertEqual(session.elements.first?.text, text.text)
        let tape = PageElement(kind: .tape, rect: CGRect(x: 40, y: 40, width: 240, height: 50))
        XCTAssertTrue(session.insertElement(tape))
        session.toggleTape(tape.id); XCTAssertTrue(session.revealedTapes.contains(tape.id))
        await session.open(page)
        XCTAssertEqual(session.elements.count, 2); XCTAssertTrue(session.revealedTapes.isEmpty)
        XCTAssertEqual(try PageElementsCodec.decode(page.objectsData).count, 2)
        let originalData = page.objectsData
        var invalid = text; invalid.width = -.infinity
        XCTAssertFalse(session.replaceElements([invalid]))
        XCTAssertEqual(page.objectsData, originalData)
        XCTAssertThrowsError(try PageElementsCodec.decode(Data("damaged".utf8)))
    }

    func testPDFMarginPreservesSourceAndExportsTextImagesShapesAndPracticeTape() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).writePDF(to: source) { renderer in
            renderer.beginPage(); UIColor.blue.setFill(); renderer.cgContext.fill(CGRect(x: 20, y: 20, width: 50, height: 50))
        }
        let originalBytes = try Data(contentsOf: source)
        let storage = DrawingStorage(root: root.appendingPathComponent("files"))
        let container = try PersistenceController.makeContainer(inMemory: true)
        let library = LibraryViewModel(context: container.mainContext, storage: storage)
        await library.importPDF(from: source, folder: nil)
        let notebook = try XCTUnwrap(library.notebooks.first), page = try XCTUnwrap(notebook.pages.first)
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        XCTAssertTrue(session.ready, session.errorMessage ?? "Page did not open")
        XCTAssertTrue(session.setMargin(300))
        XCTAssertEqual(page.logicalSize, CGSize(width: 900, height: 800))
        var text = PageElement(kind: .text, rect: CGRect(x: 70, y: 120, width: 280, height: 60)); text.text = "ATP synthesis"
        let tape = PageElement(kind: .tape, rect: CGRect(x: 60, y: 110, width: 300, height: 80))
        let rectangle = PageElement(kind: .rectangle, rect: CGRect(x: 650, y: 220, width: 150, height: 100))
        XCTAssertTrue(session.replaceElements([text, rectangle, tape]))
        let imageData = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }.pngData()!
        let added = await session.addImage(imageData); XCTAssertTrue(added)
        var photo = try XCTUnwrap(session.elements.first { $0.kind == .image })
        photo.x = 650; photo.y = 420; photo.width = 150; photo.height = 75
        session.updateElement(photo)
        XCTAssertFalse(session.setMargin(0)); XCTAssertEqual(page.pdfRightMargin, 300)
        session.errorMessage = nil
        let normalResult = await session.export(currentPageOnly: true)
        let practiceResult = await session.export(currentPageOnly: true, includeStudyTape: true)
        let normalURL = try XCTUnwrap(normalResult), practiceURL = try XCTUnwrap(practiceResult)
        defer { try? FileManager.default.removeItem(at: normalURL.deletingLastPathComponent()); try? FileManager.default.removeItem(at: practiceURL.deletingLastPathComponent()) }
        let normal = try XCTUnwrap(PDFDocument(url: normalURL)?.page(at: 0))
        let practice = try XCTUnwrap(PDFDocument(url: practiceURL)?.page(at: 0))
        XCTAssertEqual(normal.bounds(for: .mediaBox).size, page.logicalSize)
        XCTAssertTrue(normal.string?.contains("ATP synthesis") == true)
        let normalImage = render(normal, size: page.logicalSize), practiceImage = render(practice, size: page.logicalSize)
        XCTAssertGreaterThan(pixel(normalImage, x: 70, y: 180).2, 240)
        XCTAssertLessThan(pixel(practiceImage, x: 70, y: 180).2, 210)
        let red = pixel(normalImage, x: 700, y: 450)
        XCTAssertGreaterThan(red.0, 200); XCTAssertLessThan(red.2, 100)
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        let attachment = XCTAttachment(image: practiceImage); attachment.name = "Student-Tools-Practice-Export"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testRulerPreferenceAndShapePresetRemainIndependentOfInkDocuments() throws {
        let suite = "StudentTools.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tools = ToolPreferences(defaults: defaults)
        tools.selected = .pen; tools.ink.width = 5; tools.rulerEnabled = true
        let reopened = ToolPreferences(defaults: defaults)
        XCTAssertTrue(reopened.rulerEnabled); XCTAssertEqual(reopened.ink.width, 5)
        let preset = ToolPreset(name: "Red arrows", tool: .arrow, ink: InkStyle(red: 1, green: 0, blue: 0, width: 4))
        reopened.apply(preset); XCTAssertTrue(reopened.matches(preset))
        let host = CanvasHost(); host.objectsMode = true
        XCTAssertFalse(host.ink.isUserInteractionEnabled)
        host.objectsMode = false; XCTAssertTrue(host.ink.isUserInteractionEnabled)
    }
    func testSectionCommandsKeepPageIdentityAndRenderEditor() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Biology")
        let first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 1)
        container.mainContext.insert(notebook)
        container.mainContext.insert(first); container.mainContext.insert(second)
        notebook.pages = [first, second]
        let identities = Set(notebook.pages.map(\.id))
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(first)
        XCTAssertTrue(session.createSection("Cell Biology"))
        XCTAssertTrue(session.createSection("Genetics"))
        let section = try XCTUnwrap(notebook.orderedSections.first)
        session.assign(first, to: section)
        XCTAssertTrue(session.renameSection(section, title: "Organelles"))
        session.moveSection(section, offset: 1)
        XCTAssertEqual(notebook.orderedSections.last?.id, section.id)
        XCTAssertTrue(session.bookmark(first, title: "Exam topics"))
        session.deleteSection(section)
        XCTAssertNil(first.section)
        XCTAssertEqual(first.bookmarkTitle, "Exam topics")
        XCTAssertEqual(Set(notebook.pages.map(\.id)), identities)
        XCTAssertEqual(notebook.orderedPages.map(\.pageIndex), [0, 1])
        var text = PageElement(kind: .text, rect: CGRect(x: 70, y: 90, width: 500, height: 150))
        text.text = "Cell Biology\nMitochondria produce ATP."
        XCTAssertTrue(session.insertElement(text))
        XCTAssertTrue(session.insertElement(PageElement(kind: .tape, rect: CGRect(x: 70, y: 125, width: 420, height: 50))))
        let suite = "WorkflowLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        for title in ["Chemistry", "Lecture notes and observations", "Mathematics"] {
            let other = Notebook(title: title), page = NotePage(pageIndex: 0)
            container.mainContext.insert(other); container.mainContext.insert(page)
            other.pages = [page]; try container.mainContext.save()
            let opened = await workspace.open(other); XCTAssertTrue(opened)
        }
        let opened = await workspace.open(notebook); XCTAssertTrue(opened)
        let renderSession = try XCTUnwrap(workspace.activeSession)
        XCTAssertEqual(workspace.openNotebooks.count, 4)
        XCTAssertEqual(renderSession.elements.count, 2)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (size, sizeClass, scheme, name) in [
            (CGSize(width: 1180, height: 820), UserInterfaceSizeClass.regular, ColorScheme.dark, "Landscape"),
            (CGSize(width: 820, height: 1180), .regular, .dark, "Portrait"),
            (CGSize(width: 420, height: 900), .compact, .dark, "Narrow"),
            (CGSize(width: 1180, height: 820), .regular, .light, "Light")
        ] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            let host = UIHostingController(rootView: EditorView(session: renderSession, onLibrary: {}, workspace: workspace)
                .environment(\.colorScheme, scheme).environment(\.horizontalSizeClass, sizeClass))
            window.rootViewController = host; window.isHidden = false
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            await Task.yield()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Workflow-Editor-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
    }

    private func render(_ page: PDFPage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { PDFRendering.draw(page, size: size, in: $0.cgContext) }
    }
    private func pixel(_ image: UIImage, x: Int, y: Int) -> (Int, Int, Int) {
        let cg = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let index = (y * cg.width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }
}
