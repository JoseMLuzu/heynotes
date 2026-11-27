import XCTest
import SwiftData
import PencilKit
import PDFKit
import CloudKit
@testable import NotesApp

@MainActor final class SyncIncomingIntegrationTests: XCTestCase {
    func testReceivedEditableInkAndPDFSurviveRestartWhileBothLiveEditorsKeepNewerChanges() async throws {
        let root = URL.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("IncomingNative-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "IncomingNative.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let storage = DrawingStorage(root: root.appendingPathComponent("Documents"))
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 240, height: 320)).pdfData { $0.beginPage() }
        try await storage.write(pdf, to: "Source.pdf")
        let a = Notebook(title: "PDF"), b = Notebook(title: "Notes"), first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 0)
        for model: any PersistentModel in [a, b, first, second] { context.insert(model) }
        a.pages = [first]; b.pages = [second]
        first.pdfFilePath = "Source.pdf"; first.pdfPageIndex = 0; first.pageWidth = 240; first.pageHeight = 320; first.pdfRightMargin = 100
        try context.saveRecordingSyncChanges()
        let workspace = DocumentWorkspace(context: context, storage: storage, defaults: defaults)
        let opened = await workspace.open(a), beside = await workspace.openBeside(b)
        XCTAssertTrue(opened && beside)
        defer { workspace.discardPreparedPages() }
        let primary = try XCTUnwrap(workspace.primarySession), secondary = try XCTUnwrap(workspace.secondarySession)
        let ca = InkCanvas(), cb = InkCanvas(); ca.pageID = first.id; cb.pageID = second.id
        ca.drawing = ink(1); cb.drawing = ink(2); primary.canvas = ca; secondary.canvas = cb
        let key = SyncEntityIdentity(kind: .page, id: first.id).recordName
        let captured = try await workspace.captureSyncUpload(key)
        let staging = SyncUploadStagingStore(root: root.appendingPathComponent("Uploads"))
        let package = try await staging.prepare(captured), zone = CKRecordZone.ID(zoneName: "OfflineIncomingVerification")
        let wire = try await staging.cloudRecordPlan(package.manifest.id, zone: zone)
        ca.drawing = ink(3); primary.changed(ca.drawing)
        let saved = await primary.flush(); XCTAssertTrue(saved)
        let currentRevision = try XCTUnwrap(context.fetch(FetchDescriptor<SyncChange>()).first { $0.recordName == key }?.revision)
        let scope = try SyncAccountScope(containerIdentifier: "iCloud.heynotes.tests", environment: .development,
            accountRecordName: "offline-native-incoming", zone: zone)
        let libraryID = UUID(), deliveryID = UUID(), incomingURL = root.appendingPathComponent("Incoming")
        let inbox = try SyncIncomingStore(directory: incomingURL, libraryID: libraryID, scope: scope)
        // Normalize local wire proposals as explicit offline fixtures. CKRecord's server tag
        // is never manufactured, and the actual SDK adapter is not called a server success.
        let inputs = try wire.recordsToSave.map { record -> SyncIncomingInput in
            let blob = record.recordType == SyncCloudRecordPlan.blobType
            let url = try XCTUnwrap((record[blob ? "hnAsset" : "hnPayload"] as? CKAsset)?.fileURL)
            let hash = try XCTUnwrap(record[blob ? "hnHash" : "hnPayloadHash"] as? String)
            let value = SyncIncomingRecord(name: record.recordID.recordName, type: record.recordType, changeTag: "offline-native-fixture",
                revision: blob ? nil : wire.revision, tombstone: false, sha256: hash, byteCount: try SyncSourceFile(url: url).byteCount,
                blobs: (record["hnBlobs"] as? [String]) ?? [])
            return try SyncIncomingInput(record: value, sourceURL: url)
        }
        _ = try await inbox.receive(inputs, deliveryID: deliveryID)
        await inbox.close(); try await staging.discard(package.manifest.id)
        let reopened = try SyncIncomingStore(directory: incomingURL, libraryID: libraryID, scope: scope)
        let received = try await reopened.entity(key, in: deliveryID)
        let drawingURL = try XCTUnwrap(received.assetFiles["drawing"]), pdfURL = try XCTUnwrap(received.assetFiles["pdf"])
        XCTAssertEqual(try PKDrawing(data: Data(contentsOf: drawingURL)).strokes.count, 1)
        XCTAssertEqual(PDFDocument(url: pdfURL)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 240, height: 320))
        let metadata = try JSONDecoder().decode(BackupManifest.SavedPage.self, from: try XCTUnwrap(received.payload?.metadata))
        XCTAssertEqual(metadata.margin, 100); XCTAssertEqual(metadata.id, first.id); XCTAssertEqual(metadata.notebookID, a.id)
        XCTAssertEqual(primary.drawing.strokes.count, 3); XCTAssertEqual(secondary.drawing.strokes.count, 2)
        XCTAssertTrue(primary.canvas === ca && secondary.canvas === cb)
        let after = try ModelContext(container).fetch(FetchDescriptor<SyncChange>()).first { $0.recordName == key }
        XCTAssertEqual(after?.revision, currentRevision); XCTAssertNotEqual(after?.revision, wire.revision)
        let live = try await storage.read(try XCTUnwrap(first.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: live).strokes.count, 3)
        XCTAssertEqual(first.pdfFilePath, "Source.pdf")
        await reopened.close()
    }

    private func ink(_ count: Int) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { index in
            let points = [CGPoint(x: 20, y: 20 + index * 12), CGPoint(x: 120, y: 80 + index * 12)].enumerated().map {
                PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: 3, height: 3),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))
        })
    }
}
