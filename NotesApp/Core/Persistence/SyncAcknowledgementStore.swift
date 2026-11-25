import SwiftData
import Foundation

/// Own context: an acknowledgement cannot save/roll back the editor's uncommitted edits.
/// Called only through the bound state store's recovery boundary.
actor SyncAcknowledgementStore: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let libraryID: UUID
    private let save: @Sendable (ModelContext) throws -> Void

    init(modelContainer: ModelContainer, libraryID: UUID,
         save: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }) {
        self.modelContainer = modelContainer; self.libraryID = libraryID
        self.save = save
        let context = ModelContext(modelContainer); context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    func apply(_ receipts: [SyncSaveReceipt]) throws {
        guard receipts.allSatisfy({ $0.libraryID == libraryID }) else { throw SyncStateError.unknownLibrary }
        // A fresh context avoids stale pending rows after other editor saves.
        let context = ModelContext(modelContainer); context.autosaveEnabled = false
        try SyncChangeJournal.withSaveBoundary {
            do {
                for receipt in receipts {
                    try Task.checkCancellation()
                    _ = try SyncChangeJournal.acknowledge(receipt.identity.recordName, revision: receipt.revision, in: context)
                }
                try save(context)
            } catch { context.rollback(); throw error }
        }
    }
}
