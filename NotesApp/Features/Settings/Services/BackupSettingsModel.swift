import Foundation
import Observation
import SwiftData

struct BackupExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor @Observable
final class BackupSettingsModel {
    private(set) var busy = false
    private(set) var activity = ""
    var errorMessage: String?
    var notice: String?
    var exportFile: BackupExportFile?
    var prepared: PreparedLibraryBackup?
    @ObservationIgnored private let service: LibraryBackupService
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let workspace: DocumentWorkspace?
    @ObservationIgnored private var exportURL: URL?
    @ObservationIgnored private var staged: PreparedLibraryBackup?

    init(container: ModelContainer, storage: DrawingStorage = .shared, workspace: DocumentWorkspace? = nil) {
        self.container = container; self.workspace = workspace
        service = LibraryBackupService(container: container, storage: storage)
    }

    func export() async {
        guard !busy, prepared == nil else { return }
        begin("Saving notes and preparing your backup…")
        do {
            let url = try await savedLibrary { try await self.service.exportLibrary() }
            exportURL = url; exportFile = BackupExportFile(url: url)
            activity = "Choose where to save your backup."
        } catch { fail(error) }
    }

    func finishExport(saved: Bool) {
        notice = saved ? "Backup saved. Keep it in a safe location outside HeyNotes." : nil
        exportFile = nil
    }

    func cleanupExport() async {
        if let url = exportURL { exportURL = nil; await service.discardExport(url) }
        busy = false
    }

    func prepare(_ url: URL) async {
        guard !busy, prepared == nil else { return }
        begin("Checking backup integrity…")
        do {
            let backup = try await service.prepareRestore(from: url)
            staged = backup; prepared = backup; busy = false
        }
        catch { fail(error) }
    }

    func restore() async {
        guard !busy, let prepared else { return }
        begin("Restoring your library…")
        do {
            let result = try await savedLibrary { try await self.service.restore(prepared) }
            self.prepared = nil; staged = nil
            await service.discard(prepared)
            notice = "Restored \(result.notebooks) notebooks, \(result.pages) pages and \(result.cards) study cards."
            NotificationCenter.default.post(name: .libraryBackupRestored, object: nil)
            busy = false
        } catch {
            self.prepared = nil; staged = nil
            await service.discard(prepared)
            fail(error)
        }
    }

    func cancelPreparation() async {
        guard !busy, let staged else { return }
        self.prepared = nil; self.staged = nil; await service.discard(staged)
    }

    private func savedLibrary<T: Sendable>(_ operation: @MainActor () async throws -> T) async throws -> T {
        if let workspace { return try await workspace.withSavedLibrary(operation) }
        if container.mainContext.hasChanges { try container.mainContext.save() }
        return try await operation()
    }
    private func begin(_ message: String) { busy = true; activity = message; errorMessage = nil; notice = nil }
    private func fail(_ error: Error) {
        busy = false
        if !(error is CancellationError) { errorMessage = error.localizedDescription }
    }
}
