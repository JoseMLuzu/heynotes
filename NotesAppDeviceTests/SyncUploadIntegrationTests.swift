import XCTest
import SwiftData
import PencilKit
import PDFKit
import CloudKit
@testable import NotesApp

@MainActor final class SyncUploadIntegrationTests: XCTestCase {
    func testTwoLiveEditorsResumeBeforeStreamingAndKeepCapturedInkAndPDFEditable() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("SyncNative-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "SyncNative.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300)).pdfData { $0.beginPage() }
        try await storage.write(pdf, to: "Source.pdf")
        let a = Notebook(title: "PDF"), b = Notebook(title: "Notes")
        let first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 0)
        first.pdfFilePath = "Source.pdf"; first.pdfPageIndex = 0; first.pageWidth = 200; first.pageHeight = 300
        context.insert(a); context.insert(b); context.insert(first); context.insert(second)
        a.pages = [first]; b.pages = [second]; try context.saveRecordingSyncChanges()
        let workspace = DocumentWorkspace(context: context, storage: storage, defaults: defaults)
        await workspace.restore(); let opened = await workspace.open(a), beside = await workspace.openBeside(b)
        XCTAssertTrue(opened && beside)
        let primary = try XCTUnwrap(workspace.primarySession), secondary = try XCTUnwrap(workspace.secondarySession)
        defer { workspace.discardPreparedPages() }
        let ca = InkCanvas(), cb = InkCanvas(); ca.pageID = first.id; cb.pageID = second.id
        ca.drawing = ink(1); cb.drawing = ink(2); primary.canvas = ca; secondary.canvas = cb
        let key = SyncEntityIdentity(kind: .page, id: first.id).recordName
        let captured = try await workspace.captureSyncUpload(key)
        XCTAssertFalse(workspace.isSwitching)
        XCTAssertTrue(primary.canvas === ca && secondary.canvas === cb)
        let secondBytes = try await storage.read(try XCTUnwrap(second.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: secondBytes).strokes.count, 2)
        // Both editors are interactive again; a new save replaces the live file before copying.
        ca.drawing = ink(3); primary.changed(ca.drawing)
        let saved = await primary.flush(); XCTAssertTrue(saved)
        let staging = SyncUploadStagingStore(root: root.appendingPathComponent("Prepared"))
        let package = try await staging.prepare(captured)
        let drawing = try XCTUnwrap(package.manifest.assets.first { $0.role == "drawing" })
        XCTAssertEqual(try PKDrawing(data: Data(contentsOf: package.assetURL(drawing))).strokes.count, 1)
        let live = try await storage.read(try XCTUnwrap(first.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: live).strokes.count, 3)
        let source = try XCTUnwrap(package.manifest.assets.first { $0.role == "pdf" })
        XCTAssertEqual(PDFDocument(url: package.assetURL(source))?.pageCount, 1)
        XCTAssertEqual(package.cloudAssets()["drawing"]?.fileURL, package.assetURL(drawing))
        XCTAssertFalse(try SyncChangeJournal.acknowledge(key, revision: package.manifest.revision, in: context))
        let afterRestart = try await SyncUploadStagingStore(root: root.appendingPathComponent("Prepared")).load(package.manifest.id)
        XCTAssertEqual(afterRestart.manifest.revision, package.manifest.revision)
        let records = try await staging.cloudRecordPlan(afterRestart.manifest.id,
            zone: CKRecordZone.ID(zoneName: "OfflineNativeVerification"))
        let payloadURL = try XCTUnwrap((records.entity["hnPayload"] as? CKAsset)?.fileURL)
        let payload = try JSONDecoder().decode(SyncCloudPayload.self, from: Data(contentsOf: payloadURL))
        let remotePage = try JSONDecoder().decode(BackupManifest.SavedPage.self, from: payload.metadata)
        let inkRecord = try XCTUnwrap(records.blobs.first { $0.recordID.recordName == remotePage.drawing })
        let inkURL = try XCTUnwrap((inkRecord["hnAsset"] as? CKAsset)?.fileURL)
        XCTAssertEqual(try PKDrawing(data: Data(contentsOf: inkURL)).strokes.count, 1)
        let pdfRecord = try XCTUnwrap(records.blobs.first { $0.recordID.recordName == remotePage.pdf })
        let pdfURL = try XCTUnwrap((pdfRecord["hnAsset"] as? CKAsset)?.fileURL)
        XCTAssertEqual(PDFDocument(url: pdfURL)?.pageCount, 1)
        XCTAssertEqual(remotePage.pdfIndex, first.pdfPageIndex)
        XCTAssertEqual(records.identity.recordName, key)
        XCTAssertFalse(try SyncChangeJournal.acknowledge(key, revision: records.revision, in: context))
        XCTAssertTrue(primary.canvas === ca && secondary.canvas === cb)
        XCTAssertEqual(primary.drawing.strokes.count, 3)
        let archived = SyncRecordSystemFields.encode(records.entity)
        let reconstructed = try SyncRecordSystemFields.decode(archived, expecting: records.entity.recordID,
            type: SyncCloudRecordPlan.entityType)
        XCTAssertTrue(reconstructed.allKeys().isEmpty)
    }

    func testBusyOrFailedInkSaveCannotPrepareAnUploadOrClearPendingChanges() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("SyncFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "SyncFailure.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let book = Notebook(title: "Keep my ink"), page = NotePage(pageIndex: 0)
        context.insert(book); context.insert(page); book.pages = [page]; try context.saveRecordingSyncChanges()
        let workspace = DocumentWorkspace(context: context, storage: storage, defaults: defaults)
        await workspace.restore(); _ = await workspace.open(book)
        let session = try XCTUnwrap(workspace.activeSession); defer { workspace.discardPreparedPages() }
        let staging = SyncUploadStagingStore(root: root.appendingPathComponent("Prepared"))
        let key = SyncEntityIdentity(kind: .page, id: page.id).recordName
        session.auxiliaryInputActive = true
        do { _ = try await workspace.prepareSyncUpload(key, staging: staging); XCTFail("Busy editor must reject capture") }
        catch LibraryBackupError.busy {} catch { XCTFail("Unexpected error: \(error)") }
        session.auxiliaryInputActive = false
        try await storage.write(Data([7]), to: "blocked")
        page.drawingFilePath = "blocked/ink.drawing"; session.changed(ink(1))
        do { _ = try await workspace.prepareSyncUpload(key, staging: staging); XCTFail("Failed save must reject capture") }
        catch LibraryBackupError.savePending {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(session.hasPendingSave); XCTAssertFalse(workspace.isSwitching)
        let packages = try await staging.packageIDs(); XCTAssertTrue(packages.isEmpty)
        let retained = try await storage.read("blocked"); XCTAssertEqual(retained, Data([7]))
        XCTAssertGreaterThan(try ModelContext(container).fetchCount(FetchDescriptor<SyncChange>()), 0)
    }

    private func ink(_ count: Int) -> PKDrawing {
        let point = PKStrokePoint(location: CGPoint(x: 20, y: 20), timeOffset: 0, size: CGSize(width: 3, height: 3),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let stroke = PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: [point], creationDate: .now))
        return PKDrawing(strokes: Array(repeating: stroke, count: count))
    }
}
