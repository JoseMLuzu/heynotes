import XCTest
import SwiftUI
import SwiftData
import PencilKit
import PDFKit
@testable import NotesApp

@MainActor final class DataRecoveryPrivacyTests: XCTestCase {
    func testRemovingLivePDFPageRetainsEditableInkAndStudyLinkThroughBackup() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("library.store"))
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents")), context = container.mainContext
        let book = Notebook(title: "Biology"), page = NotePage(pageIndex: 1)
        let first = NotePage(pageIndex: 0), last = NotePage(pageIndex: 2)
        for value: any PersistentModel in [book, first, page, last] { context.insert(value) }
        book.pages = [first, page, last]
        let source = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 200)).pdfData { renderer in
            renderer.beginPage(); ("Original PDF" as NSString).draw(at: CGPoint(x: 20, y: 20))
        }
        try await storage.write(source, to: "Sources/lecture.pdf")
        page.pdfFilePath = "Sources/lecture.pdf"; page.pdfPageIndex = 0; page.pageWidth = 300; page.pageHeight = 200
        page.pdfRightMargin = 120; page.bookmarkTitle = "Exam"
        try context.saveRecordingSyncChanges()
        let study = StudyViewModel(container: container)
        let deck = try study.saveDeck(title: "Cells", notebookID: book.id)
        let card = try study.saveCard(deckID: deck.id, question: "Q", answer: "A", source: .init(notebookID: book.id, pageID: page.id))
        let session = EditorSession(notebook: book, context: context, storage: storage)
        defer { session.discardPreparedPages() }
        await session.open(page)
        let canvas = InkCanvas(); canvas.pageID = page.id; canvas.drawing = ink(); session.canvas = canvas
        XCTAssertFalse(session.hasPendingSave) // Pending delegate callbacks must not lose final ink.
        await session.deletePage()
        XCTAssertNotNil(page.trashedAt); XCTAssertEqual(book.activePageCount, 2); XCTAssertEqual(book.pages.count, 3)
        XCTAssertEqual(session.page?.id, first.id)
        let path = try XCTUnwrap(page.drawingFilePath)
        let bytes = try await storage.read(path)
        XCTAssertEqual(try PKDrawing(data: bytes), canvas.drawing)
        XCTAssertThrowsError(try study.source(for: card))
        let exportResult = await session.export(currentPageOnly: false)
        let exported = try XCTUnwrap(exportResult)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        XCTAssertEqual(PDFDocument(url: exported)?.pageCount, 2)
        let backupService = LibraryBackupService(container: container, storage: storage)
        let archive = try await backupService.exportLibrary()
        defer { Task { await backupService.discardExport(archive) } }
        let prepared = try await backupService.prepareRestore(from: archive)
        defer { Task { await backupService.discard(prepared) } }
        let restoredContainer = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("restored.store"))
        let restoredStorage = DrawingStorage(root: root.appendingPathComponent("RestoredDocuments"))
        _ = try await LibraryBackupService(container: restoredContainer, storage: restoredStorage).restore(prepared)
        let recoveredBook = try XCTUnwrap(restoredContainer.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        let recovered = try XCTUnwrap(recoveredBook.removedPages.first)
        XCTAssertEqual(recovered.id, page.id); XCTAssertEqual(recovered.pdfRightMargin, 120); XCTAssertEqual(recovered.bookmarkTitle, "Exam")
        let restoredCard = try XCTUnwrap(restoredContainer.mainContext.fetch(FetchDescriptor<Flashcard>()).first)
        XCTAssertEqual(restoredCard.sourcePageID, recovered.id)
        let recoveredSession = EditorSession(notebook: recoveredBook, context: restoredContainer.mainContext, storage: restoredStorage)
        defer { recoveredSession.discardPreparedPages() }
        await recoveredSession.restorePage(recovered)
        XCTAssertEqual(recoveredBook.orderedPages[1].id, page.id)
        await recoveredSession.open(recovered)
        XCTAssertTrue(recoveredSession.ready); XCTAssertNotNil(recoveredSession.pdfBackground)
        XCTAssertEqual(recoveredSession.drawing, canvas.drawing)
        let recoveredStudy = StudyViewModel(container: restoredContainer)
        XCTAssertEqual(try recoveredStudy.source(for: restoredCard).pageID, page.id)
        let retained = try await storage.read("Sources/lecture.pdf")
        XCTAssertEqual(retained, source)
    }

    func testPrivacyManifestIsBundledAndMatchesCurrentLocalAPIUses() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.count, 0)
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: entries.map { ($0["NSPrivacyAccessedAPIType"] as! String, $0["NSPrivacyAccessedAPITypeReasons"] as! [String]) })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1", "3B52.1"])
        XCTAssertEqual(reasons.count, 2)
    }

    func testRecoveryAndOfflinePrivacyScreensRenderAtAccessibleSizes() async throws {
        try await capture(AnyView(NavigationStack { PrivacyView() }), name: "Privacy", size: CGSize(width: 820, height: 1180))
        try await capture(AnyView(NavigationStack { DataRecoveryView() }.environment(\.dynamicTypeSize, .accessibility3).preferredColorScheme(.dark)),
                          name: "Recovery-Accessible", size: CGSize(width: 540, height: 820))
        let container = try PersistenceController.makeContainer(inMemory: true), book = Notebook(title: "Biology")
        let first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 1)
        for value: any PersistentModel in [book, first, second] { container.mainContext.insert(value) }
        book.pages = [first, second]; second.bookmarkTitle = "Cell structure"
        XCTAssertTrue(PageRecovery.remove(second, from: book)); try container.mainContext.saveRecordingSyncChanges()
        let session = EditorSession(notebook: book, context: container.mainContext)
        try await capture(AnyView(RemovedPagesView(session: session).modelContainer(container)), name: "Removed-Pages", size: CGSize(width: 620, height: 820))
        try await capture(AnyView(RemovedPagesView(session: session).modelContainer(container).environment(\.dynamicTypeSize, .accessibility3)),
                          name: "Removed-Pages-Accessible", size: CGSize(width: 540, height: 820))
    }

    private func ink() -> PKDrawing {
        let points = [CGPoint(x: 30, y: 40), CGPoint(x: 150, y: 90)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }

    private func capture(_ content: AnyView, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250)); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/heynotes-\(name).png"))
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
