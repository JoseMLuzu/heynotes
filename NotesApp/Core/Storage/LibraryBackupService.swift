import Foundation
import SwiftData

/// Coordinates actor-isolated metadata with the same serialized file store used by the editor.
actor LibraryBackupService {
    private let container: ModelContainer
    private let storage: DrawingStorage
    private let save: @Sendable (ModelContext) throws -> Void

    init(container: ModelContainer, storage: DrawingStorage = .shared,
         save: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }) {
        self.container = container; self.storage = storage; self.save = save
    }
    func exportLibrary() async throws -> URL {
        let metadata = BackupMetadataStore(modelContainer: container)
        let manifest = try await metadata.capture()
        return try await storage.createLibraryBackup(manifest)
    }
    func prepareRestore(from source: URL) throws -> PreparedLibraryBackup { try BackupArchive.prepare(source) }

    func restore(_ prepared: PreparedLibraryBackup) async throws -> BackupRestoreResult {
        try BackupValidation.manifest(prepared.manifest)
        let prefix = "Restored/\(UUID().uuidString)"
        try await storage.installLibraryBackup(prepared, prefix: prefix)
        let paths = Dictionary(uniqueKeysWithValues: prepared.files.map { ($0.path, "\(prefix)/\($0.path)") })
        do {
            let metadata = BackupMetadataStore(modelContainer: container)
            return try await metadata.restore(prepared.manifest, paths: paths, save: save)
        } catch {
            // Remove only this failed, unreferenced import; pre-existing files are never touched.
            try? await storage.removeFailedLibraryBackup(prefix: prefix)
            throw error
        }
    }
    func discard(_ prepared: PreparedLibraryBackup) { BackupArchiveIO.discardTemporary(prepared.directory) }
    func discardExport(_ url: URL) { BackupArchiveIO.discardTemporary(url.deletingLastPathComponent()) }
}

extension Notification.Name {
    static let libraryBackupRestored = Notification.Name("HeyNotes.libraryBackupRestored")
}
