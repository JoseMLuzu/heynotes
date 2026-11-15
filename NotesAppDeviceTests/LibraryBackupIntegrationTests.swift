import XCTest
import SwiftUI
import SwiftData
import PencilKit
import PDFKit
import UniformTypeIdentifiers
@testable import NotesApp

@MainActor final class LibraryBackupIntegrationTests: XCTestCase {
    func testBackupFlushesBothNativeCanvasesAndRestoresEditableInkPDFAndStudyLinks() async throws {
        let f = try NativeBackupFixture(); defer { f.cleanup() }
        let source = f.root.appendingPathComponent("Lecture.pdf")
        let pdfBytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 200)).pdfData { context in
            context.beginPage(); ("Original lecture" as NSString).draw(at: CGPoint(x: 20, y: 20))
        }
        try pdfBytes.write(to: source)
        let library = LibraryViewModel(context: f.container.mainContext, storage: f.storage)
        let imported = await library.importPDF(from: source, folder: nil); XCTAssertTrue(imported)
        let pdf = try XCTUnwrap(library.notebooks.first { $0.pages.first?.pdfFilePath != nil })
        _ = await f.workspace.open(f.book); _ = await f.workspace.openBeside(pdf)
        let a = try XCTUnwrap(f.workspace.primarySession), b = try XCTUnwrap(f.workspace.secondarySession)
        let ac = InkCanvas(), bc = InkCanvas()
        ac.pageID = a.page?.id; bc.pageID = b.page?.id
        ac.drawing = ink(.blue); bc.drawing = ink(.red)
        a.canvas = ac; b.canvas = bc
        // No delegate notification: the backup boundary must capture live UIKit ink itself.
        XCTAssertFalse(a.hasPendingSave || b.hasPendingSave)
        let study = StudyViewModel(container: f.container)
        let deck = try study.saveDeck(title: "Lecture", notebookID: pdf.id)
        let card = try study.saveCard(deckID: deck.id, question: "Source?", answer: "Lecture",
                                     source: .init(notebookID: pdf.id, pageID: try XCTUnwrap(b.page?.id)))
        try study.review(card.id, rating: .good, at: .now)
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await f.workspace.withSavedLibrary {
            XCTAssertTrue(f.workspace.blocksNavigation)
            let opened = await f.workspace.showLibrary(); XCTAssertFalse(opened)
            return try await service.exportLibrary()
        }
        defer { Task { await service.discardExport(url) } }
        XCTAssertFalse(f.workspace.isSwitching || a.hasPendingSave || b.hasPendingSave)
        XCTAssertTrue(a.canvas === ac && b.canvas === bc)
        XCTAssertEqual(ac.drawing.strokes.count, 1); XCTAssertEqual(bc.drawing.strokes.count, 1)
        let prepared = try await service.prepareRestore(from: url)
        defer { Task { await service.discard(prepared) } }
        let target = try NativeBackupFixture(seed: false); defer { target.cleanup() }
        let restore = LibraryBackupService(container: target.container, storage: target.storage)
        _ = try await restore.restore(prepared)
        let context = ModelContext(target.container)
        let books = try context.fetch(FetchDescriptor<Notebook>())
        let restored = try XCTUnwrap(books.first { $0.id == pdf.id })
        let page = try XCTUnwrap(restored.pages.first)
        let session = EditorSession(notebook: restored, context: context, storage: target.storage)
        await session.open(page); defer { session.discardPreparedPages() }
        XCTAssertTrue(session.ready); XCTAssertNotNil(session.pdfBackground)
        XCTAssertEqual(session.drawing, bc.drawing)
        let note = try XCTUnwrap(books.first { $0.id == f.book.id })
        let noteBytes = try await target.storage.read(try XCTUnwrap(note.pages.first?.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: noteBytes), ac.drawing)
        let restoredPDF = try await target.storage.read(try XCTUnwrap(page.pdfFilePath))
        XCTAssertEqual(restoredPDF, pdfBytes); XCTAssertEqual(try Data(contentsOf: source), pdfBytes)
        let resultURL = await session.export(currentPageOnly: true)
        let exported = try XCTUnwrap(resultURL)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        XCTAssertEqual(PDFDocument(url: exported)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 300, height: 200))
        let restoredCard = try XCTUnwrap(context.fetch(FetchDescriptor<Flashcard>()).first)
        XCTAssertEqual(restoredCard.sourcePageID, page.id); XCTAssertEqual(restoredCard.sourceNotebookID, restored.id)
        XCTAssertEqual(restoredCard.deck?.notebookID, restored.id); XCTAssertEqual(restoredCard.reviews.count, 1)
    }

    func testFailedEditorSavePreventsBackupAndKeepsPendingInkAndCanvas() async throws {
        let f = try NativeBackupFixture(blocked: true); defer { f.cleanup() }
        _ = await f.workspace.open(f.book)
        let session = try XCTUnwrap(f.workspace.activeSession), canvas = InkCanvas()
        canvas.pageID = session.page?.id; canvas.drawing = ink(.blue); session.canvas = canvas
        var called = false
        do {
            _ = try await f.workspace.withSavedLibrary { called = true; return 1 }
            XCTFail("A backup must not start after a failed canvas save")
        } catch { XCTAssertNotNil(error as? LibraryBackupError) }
        XCTAssertFalse(called || f.workspace.isSwitching)
        XCTAssertTrue(session.canvas === canvas && session.hasPendingSave)
        XCTAssertEqual(canvas.drawing.strokes.count, 1); XCTAssertNotNil(session.errorMessage)
    }

    func testSettingsExportCancelRestoreAndDismissedPreviewCleanTemporaryFiles() async throws {
        let f = try NativeBackupFixture(); defer { f.cleanup() }
        let model = BackupSettingsModel(container: f.container, storage: f.storage, workspace: f.workspace)
        await model.export()
        let file = try XCTUnwrap(model.exportFile)
        XCTAssertTrue(model.busy); XCTAssertNil(model.notice)
        var completions: [Bool] = []
        let delegate = BackupExportPicker.Coordinator { completions.append($0) }
        let native = UIDocumentPickerViewController(forExporting: [file.url], asCopy: true)
        delegate.documentPickerWasCancelled(native)
        delegate.documentPicker(native, didPickDocumentsAt: [file.url])
        XCTAssertEqual(completions, [false])
        model.finishExport(saved: true)
        XCTAssertNotNil(model.notice)
        await model.prepare(file.url) // Still exporting; must be ignored.
        XCTAssertNil(model.prepared)
        // Retain a user-owned copy before cleaning the temporary export.
        let saved = f.root.appendingPathComponent("Saved.heynotesbackup")
        try FileManager.default.copyItem(at: file.url, to: saved)
        await model.cleanupExport()
        XCTAssertFalse(model.busy); XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        await model.prepare(saved)
        let preview = try XCTUnwrap(model.prepared)
        XCTAssertEqual(preview.manifest.notebooks.count, 1)
        model.prepared = nil // SwiftUI clears its sheet binding on interactive dismissal.
        await model.cancelPreparation()
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.directory.path))
        await model.prepare(saved); await model.restore()
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.prepared); XCTAssertFalse(model.busy)
        XCTAssertEqual(try ModelContext(f.container).fetchCount(FetchDescriptor<Notebook>()), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertTrue(UTType.heyNotesBackup.conforms(to: .data))
        XCTAssertEqual(UTType(filenameExtension: "heynotesbackup"), .heyNotesBackup)
    }

    func testBackupScreensRenderWithRealCountsInLightDarkAndAccessibleLayouts() async throws {
        let f = try NativeBackupFixture(); defer { f.cleanup() }
        let service = LibraryBackupService(container: f.container, storage: f.storage)
        let url = try await service.exportLibrary(); defer { Task { await service.discardExport(url) } }
        let backup = try await service.prepareRestore(from: url); defer { Task { await service.discard(backup) } }
        try await capture(AnyView(NavigationStack {
            BackupSettingsView(container: f.container, workspace: f.workspace, working: .constant(false))
        }), name: "Library-Backups", size: CGSize(width: 820, height: 1180))
        try await capture(AnyView(BackupRestorePreview(backup: backup, busy: false, restore: {}, cancel: {})
            .preferredColorScheme(.dark)), name: "Restore-Verified-Backup-Dark", size: CGSize(width: 1180, height: 820))
        try await capture(AnyView(BackupRestorePreview(backup: backup, busy: true, restore: {}, cancel: {})
            .environment(\.dynamicTypeSize, .accessibility3)), name: "Restore-Accessible-Narrow", size: CGSize(width: 540, height: 820))
    }

    private func capture(_ content: AnyView, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250)); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if name == "Library-Backups" { try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/heynotes-backup-settings.png")) }
    }

    private func ink(_ color: UIColor) -> PKDrawing {
        let points = [CGPoint(x: 30, y: 40), CGPoint(x: 150, y: 90)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }
}

@MainActor private final class NativeBackupFixture {
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let container: ModelContainer
    let storage: DrawingStorage
    let workspace: DocumentWorkspace
    let book = Notebook(title: "Biology")
    let suite = "NativeBackups.\(UUID())"
    let defaults: UserDefaults
    init(seed: Bool = true, blocked: Bool = false) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("library.store"))
        let documents = root.appendingPathComponent("Documents")
        if blocked { try Data([0]).write(to: documents) }
        storage = DrawingStorage(root: documents)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        workspace = DocumentWorkspace(context: container.mainContext, storage: storage, defaults: defaults)
        if seed {
            let page = NotePage(pageIndex: 0)
            container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
            try container.mainContext.save()
        }
    }
    func cleanup() {
        workspace.discardPreparedPages(); defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
