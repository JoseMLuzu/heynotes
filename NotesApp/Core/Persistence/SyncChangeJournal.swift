import Foundation
import SwiftData

extension ModelContext {
    /// User metadata and pending sync intent share one local transaction, never two saves.
    func saveRecordingSyncChanges() throws {
        try SyncChangeJournal.recordPendingChanges(in: self)
        try save()
    }
}

enum SyncChangeJournal {
    static func identity(of model: any PersistentModel) -> SyncEntityIdentity? {
        switch model {
        case let value as Folder: .init(kind: .folder, id: value.id)
        case let value as Notebook: .init(kind: .notebook, id: value.id)
        case let value as NotePage: .init(kind: .page, id: value.id)
        case let value as NotebookSection: .init(kind: .section, id: value.id)
        case let value as StudyDeck: .init(kind: .deck, id: value.id)
        case let value as Flashcard: .init(kind: .card, id: value.id)
        case let value as ReviewRecord: .init(kind: .review, id: value.id)
        default: nil // The journal never records its own mutations.
        }
    }

    static func recordPendingChanges(in context: ModelContext) throws {
        var changes: [SyncEntityIdentity: SyncChangeOperation] = [:]
        for model in context.insertedModelsArray + context.changedModelsArray {
            if let identity = identity(of: model) { changes[identity] = .upsert }
        }
        var deletions = context.deletedModelsArray
        var visited = Set<SyncEntityIdentity>()
        while let model = deletions.popLast() {
            guard let identity = identity(of: model), visited.insert(identity).inserted else { continue }
            changes[identity] = .delete
            // Capture cascade identities while the models are still registered, before save.
            switch model {
            case let notebook as Notebook: deletions += notebook.pages; deletions += notebook.sections
            case let deck as StudyDeck: deletions += deck.cards
            case let card as Flashcard: deletions += card.reviews
            case let folder as Folder:
                for survivor in (folder.children as [any PersistentModel]) + folder.notebooks {
                    if let key = self.identity(of: survivor), changes[key] != .delete { changes[key] = .upsert }
                }
            case let section as NotebookSection:
                for page in section.pages {
                    let key = SyncEntityIdentity(kind: .page, id: page.id)
                    if changes[key] != .delete { changes[key] = .upsert }
                }
            default: break
            }
        }
        guard !changes.isEmpty else { return }
        let keys = changes.keys.map(\.recordName)
        var existing: [String: SyncChange] = [:]
        // Bound SQL predicate size for PDF imports and large additive restores.
        for start in stride(from: 0, to: keys.count, by: 100) {
            let batch = Array(keys[start..<min(start + 100, keys.count)])
            for row in try context.fetch(FetchDescriptor<SyncChange>(predicate: #Predicate { batch.contains($0.recordName) })) {
                existing[row.recordName] = row
            }
        }
        let now = Date.now
        for (identity, operation) in changes {
            if let row = existing[identity.recordName] {
                row.operationRawValue = operation.rawValue; row.revision = UUID(); row.changedAt = now
            } else {
                context.insert(SyncChange(identity: identity, operation: operation, now: now))
            }
        }
    }

    /// Stages removal only for the exact revision a future transport successfully sent.
    /// The caller commits this together with any server metadata; a newer edit stays pending.
    @discardableResult static func acknowledge(_ recordName: String, revision: UUID, in context: ModelContext) throws -> Bool {
        let rows = try context.fetch(FetchDescriptor<SyncChange>(predicate: #Predicate { $0.recordName == recordName }))
        guard let row = rows.first, row.revision == revision else { return false }
        context.delete(row)
        return true
    }
}
