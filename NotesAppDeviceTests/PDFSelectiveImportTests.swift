import XCTest
import SwiftUI
import SwiftData
import PDFKit
import PencilKit
@testable import NotesApp

@MainActor final class PDFSelectiveImportTests: XCTestCase {
    func testRangesValidateBoundsDeduplicateAndPreserveDocumentOrder() throws {
        XCTAssertEqual(try PDFPageSelection.parse("1, 3–5, 3, 8", pageCount: 8), [0, 2, 3, 4, 7])
        XCTAssertEqual(try PDFPageSelection.parse(" 4 , 2-3, 1 ", pageCount: 4), [0, 1, 2, 3])
        XCTAssertEqual(try PDFPageSelection.parse("2", pageCount: 4), [1])
        for text in ["", "0", "5", "2-1", "-1", "1-", "1,,2", "1-2-3", "two", "1.5", "9999999999999999999999999999"] {
            XCTAssertThrowsError(try PDFPageSelection.parse(text, pageCount: 4), text)
        }
        XCTAssertThrowsError(try PDFPageSelection.validated([], pageCount: 4))
        XCTAssertThrowsError(try PDFPageSelection.validated([-1], pageCount: 4))
        XCTAssertThrowsError(try PDFPageSelection.validated([4], pageCount: 4))
    }

    func testSelectionStartsWithAllAndSingleTapCanChooseOnePage() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let draft = try await fixture.staging.prepare(fixture.source)
        let selection = PDFImportSelection(draft: draft)
        XCTAssertEqual(selection.indices, [0, 1, 2, 3]); XCTAssertTrue(selection.canImport)
        selection.toggle(2)
        XCTAssertEqual(selection.mode, .selected); XCTAssertEqual(selection.indices, [2])
        selection.toggle(0); XCTAssertEqual(selection.indices, [0, 2])
        selection.toggle(2); XCTAssertEqual(selection.indices, [0])
        selection.rangeText = "2–3"; selection.applyRange()
        XCTAssertEqual(selection.indices, [1, 2]); XCTAssertNil(selection.rangeError)
        selection.rangeText = "9"; selection.applyRange()
        XCTAssertNotNil(selection.rangeError); XCTAssertFalse(selection.canImport)
        selection.clear(); XCTAssertFalse(selection.canImport)
        selection.mode = .all; XCTAssertEqual(selection.indices.count, 4)
        let failed = await selection.confirm { _ in "A recoverable import error" }
        XCTAssertFalse(failed); XCTAssertEqual(selection.errorMessage, "A recoverable import error")
        XCTAssertFalse(selection.importing); XCTAssertTrue(selection.canImport)
        let succeeded = await selection.confirm { indices in XCTAssertEqual(indices, [0, 1, 2, 3]); return nil }
        XCTAssertTrue(succeeded)
        await fixture.staging.discard(draft)
    }

    func testCancelDiscardsOnlyStagedCopyAndCreatesNoNotebook() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let bytes = try Data(contentsOf: fixture.source)
        let draft = try await fixture.staging.prepare(fixture.source)
        XCTAssertEqual(draft.pageCount, 4)
        XCTAssertNotEqual(draft.sourceURL, fixture.source)
        _ = try await PDFDocumentService.importPreviews.background(path: draft.document.path, index: 2, storage: draft.storage, maxPixels: 180)
        await fixture.staging.discard(draft)
        await fixture.staging.discard(draft) // Repeated sheet cleanup is harmless.
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.sourceURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.source), bytes)
        XCTAssertEqual(try fixture.store.mainContext.fetchCount(FetchDescriptor<Notebook>()), 0)
    }

    func testRepeatedConfirmationCannotImportTwiceOrChangeSelectionDuringCopy() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let draft = try await fixture.staging.prepare(fixture.source)
        let selection = PDFImportSelection(draft: draft)
        selection.toggle(1)
        var calls = 0
        var resume: CheckedContinuation<String?, Never>?
        let pending = Task {
            await selection.confirm { indices in
                calls += 1; XCTAssertEqual(indices, [1])
                return await withCheckedContinuation { resume = $0 }
            }
        }
        for _ in 0..<100 {
            if selection.importing { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(selection.importing)
        selection.toggle(2); selection.clear()
        XCTAssertEqual(selection.indices, [1])
        let repeated = await selection.confirm { _ in calls += 1; return nil }
        XCTAssertFalse(repeated); XCTAssertEqual(calls, 1)
        try XCTUnwrap(resume).resume(returning: nil)
        let result = await pending.value
        XCTAssertTrue(result); XCTAssertFalse(selection.importing)
        await fixture.staging.discard(draft)
    }

    func testSelectedOriginalIndicesRetainRotationEditableInkAndExportOnlyChosenPages() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let original = try Data(contentsOf: fixture.source)
        let draft = try await fixture.staging.prepare(fixture.source)
        let imported = await fixture.model.importPDF(from: draft.sourceURL, folder: nil, selectedPageIndices: [2, 0, 2], title: draft.title)
        XCTAssertTrue(imported); XCTAssertNil(fixture.model.errorMessage)
        let notebook = try XCTUnwrap(fixture.model.notebooks.first)
        XCTAssertEqual(notebook.title, "Semester")
        XCTAssertEqual(notebook.orderedPages.map(\.pageIndex), [0, 1])
        XCTAssertEqual(notebook.orderedPages.map(\.pdfPageIndex), [0, 2])
        XCTAssertEqual(notebook.orderedPages.map(\.logicalSize), [CGSize(width: 200, height: 300), CGSize(width: 300, height: 200)])
        let path = try XCTUnwrap(notebook.orderedPages.first?.pdfFilePath)
        XCTAssertEqual(Set(notebook.pages.compactMap(\.pdfFilePath)).count, 1)
        let privateCopy = try await fixture.storage.read(path)
        XCTAssertEqual(privateCopy, original)
        await fixture.staging.discard(draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.sourceURL.path))
        let session = EditorSession(notebook: notebook, context: fixture.store.mainContext, storage: fixture.storage)
        defer { session.discardPreparedPages() }
        await session.open(notebook.orderedPages[1])
        XCTAssertTrue(session.ready); XCTAssertNotNil(session.pdfBackground)
        let points = [CGPoint(x: 30, y: 100), CGPoint(x: 160, y: 100)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        session.changed(PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))]))
        let saved = await session.flush(); XCTAssertTrue(saved)
        let exported = await session.export(currentPageOnly: false)
        let url = try XCTUnwrap(exported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Source Page 1") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Source Page 3") == true)
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 300, height: 200))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format).image {
            PDFRendering.draw(pdf.page(at: 1)!, size: CGSize(width: 300, height: 200), in: $0.cgContext)
        }
        let blue = pixel(image, x: 80, y: 100)
        XCTAssertGreaterThan(blue.2, 180); XCTAssertLessThan(blue.0, 100)
        XCTAssertEqual(try Data(contentsOf: fixture.source), original)
    }

    func testStagingSurvivesSourceRemovalAndInvalidSelectionsCreateNoMetadata() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let draft = try await fixture.staging.prepare(fixture.source)
        try FileManager.default.removeItem(at: fixture.source)
        for indices in [[], [-1], [4]] {
            let success = await fixture.model.importPDF(from: draft.sourceURL, folder: nil, selectedPageIndices: indices, title: draft.title)
            XCTAssertFalse(success)
            XCTAssertEqual(try fixture.store.mainContext.fetchCount(FetchDescriptor<Notebook>()), 0)
        }
        let success = await fixture.model.importPDF(from: draft.sourceURL, folder: nil, selectedPageIndices: [1], title: draft.title)
        XCTAssertTrue(success)
        XCTAssertEqual(fixture.model.notebooks.first?.pages.count, 1)
        XCTAssertEqual(fixture.model.notebooks.first?.pages.first?.pdfPageIndex, 1)
        await fixture.staging.discard(draft)
    }

    func testSelectorOpensExpandedWithRealThumbnailsInPortraitAndLandscape() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let draft = try await fixture.staging.prepare(fixture.source)
        for size in [CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820)] {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
            let state = ImportSheetState()
            let host = UIHostingController(rootView: ImportSheetHost(state: state, draft: draft))
            window.rootViewController = host; window.isHidden = false
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80)); state.visible = true
            for _ in 0..<100 {
                if host.presentedViewController?.view.window != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let presented = try XCTUnwrap(host.presentedViewController)
            try await Task.sleep(for: .milliseconds(500)); presented.view.layoutIfNeeded()
            let frame = presented.view.convert(presented.view.bounds, to: window)
            XCTAssertGreaterThan(frame.height, window.bounds.height * 0.8)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "PDF-Page-Selector-\(Int(size.width))"
            attachment.lifetime = .keepAlways; add(attachment)
            let segmented = try XCTUnwrap(descendants(presented.view).compactMap { $0 as? UISegmentedControl }.first)
            segmented.selectedSegmentIndex = 1
            segmented.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(100)); presented.view.layoutIfNeeded()
            XCTAssertTrue(descendants(presented.view).contains { $0 is UITextField })
            let selectedImage = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let selectedAttachment = XCTAttachment(image: selectedImage); selectedAttachment.name = "PDF-Choose-Pages-\(Int(size.width))"
            selectedAttachment.lifetime = .keepAlways; add(selectedAttachment)
            state.visible = false; host.dismiss(animated: false)
            window.isHidden = true; window.rootViewController = nil
        }
        await fixture.staging.discard(draft)
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

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

@MainActor private final class ImportSheetState: ObservableObject { @Published var visible = false }
@MainActor private struct ImportSheetHost: View {
    @ObservedObject var state: ImportSheetState
    let draft: PDFImportDraft
    var body: some View {
        Color.clear.sheet(isPresented: $state.visible) {
            PDFPageSelectionView(draft: draft, close: { state.visible = false }) { _ in nil }
        }
    }
}

@MainActor private final class ImportFixture {
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source: URL
    let staging: PDFImportStaging
    let store: ModelContainer
    let storage: DrawingStorage
    let model: LibraryViewModel
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appendingPathComponent("Semester.pdf")
        staging = PDFImportStaging(root: root.appendingPathComponent("Staging"))
        storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        store = try PersistenceController.makeContainer(inMemory: true)
        model = LibraryViewModel(context: store.mainContext, storage: storage)
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300)).writePDF(to: source) { renderer in
            for (index, size) in [CGSize(width: 200, height: 300), CGSize(width: 400, height: 200), CGSize(width: 200, height: 300), CGSize(width: 300, height: 300)].enumerated() {
                renderer.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size))
                ("Source Page \(index + 1)" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
        let pdf = PDFDocument(url: source)!
        pdf.page(at: 1)?.setBounds(CGRect(x: 20, y: 10, width: 360, height: 180), for: .cropBox)
        pdf.page(at: 2)?.rotation = 90
        guard pdf.write(to: source) else { throw DocumentError.unreadable }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
