import Foundation
import SwiftData

@ModelActor actor SyncUploadMetadataStore {
    /// Read committed metadata after all active editors have flushed, before pinning files.
    func capture(_ recordName: String) throws -> SyncUploadPlan {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let change = try context.fetch(FetchDescriptor<SyncChange>(predicate: #Predicate { $0.recordName == recordName })).first,
              let kind = SyncEntityKind(rawValue: change.kindRawValue),
              let operation = SyncChangeOperation(rawValue: change.operationRawValue) else { throw SyncUploadError.unavailableRevision }
        let identity = SyncEntityIdentity(kind: kind, id: change.entityID)
        guard identity.recordName == recordName else { throw SyncUploadError.invalidSnapshot }
        var sources: [SyncAssetSource] = []
        func encode<T: Encodable>(_ value: T) throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return try encoder.encode(value)
        }
        let id = identity.id
        let payload: Data?
        if operation == .delete { payload = nil }
        else {
            switch kind {
            case .folder:
                guard let value = try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })).first else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedFolder(value))
            case .notebook:
                guard let value = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })).first else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedNotebook(value))
            case .section:
                guard let value = try context.fetch(FetchDescriptor<NotebookSection>(predicate: #Predicate { $0.id == id })).first else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedSection(value))
            case .page:
                guard let value = try context.fetch(FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == id })).first,
                      let notebookID = value.notebook?.id else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedPage(value))
                sources.append(.init(role: "drawing", path: value.drawingFilePath ?? DrawingStorage.path(notebook: notebookID, page: id), allowsMissing: value.drawingFilePath == nil))
                if let path = value.pdfFilePath { sources.append(.init(role: "pdf", path: path)) }
                for element in try PageElementsCodec.decode(value.objectsData) {
                    if let path = element.imagePath {
                        sources.append(.init(role: "image.\(element.id.uuidString.lowercased())", path: path))
                    }
                    if let path = element.fontFilePath {
                        sources.append(.init(role: "font.\(element.id.uuidString.lowercased())", path: path))
                    }
                }
            case .deck:
                guard let value = try context.fetch(FetchDescriptor<StudyDeck>(predicate: #Predicate { $0.id == id })).first else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedDeck(value))
            case .card:
                guard let value = try context.fetch(FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == id })).first else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedCard(value))
                if let path = value.questionImagePath { sources.append(.init(role: "question", path: path)) }
                if let path = value.answerImagePath { sources.append(.init(role: "answer", path: path)) }
            case .review:
                guard let value = try context.fetch(FetchDescriptor<ReviewRecord>(predicate: #Predicate { $0.id == id })).first else { throw SyncUploadError.missingEntity }
                payload = try encode(BackupManifest.SavedReview(value))
            }
        }
        return SyncUploadPlan(identity: identity, revision: change.revision, operation: operation, metadata: payload, sources: sources)
    }
}
