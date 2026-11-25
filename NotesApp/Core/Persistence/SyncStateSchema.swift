import Foundation
import SwiftData

/// A separate device-local store. These models never enter the V8 user schema or backups.
enum SyncStateSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Library.self, Record.self, Receipt.self] }

    @Model final class Library {
        @Attribute(.unique) var localName: String
        @Attribute(.unique) var id: UUID
        var scopeData: Data?
        var scopeKey: String?
        var activeGeneration: UUID?
        var engineData: Data?
        var engineSequence: Int64
        init(localName: String) {
            self.localName = localName; id = UUID(); engineSequence = 0
        }
    }

    @Model final class Record {
        @Attribute(.unique) var key: String
        var scopeKey: String
        var name: String
        var type: String
        var fields: Data
        var version: UUID
        init(key: String, scopeKey: String, name: String, type: String, fields: Data) {
            self.key = key; self.scopeKey = scopeKey; self.name = name; self.type = type
            self.fields = fields; version = UUID()
        }
    }

    @Model final class Receipt {
        @Attribute(.unique) var id: UUID
        var libraryID: UUID
        var scopeKey: String
        var kind: String
        var entityID: UUID
        var revision: UUID
        var packageID: UUID
        init(id: UUID, libraryID: UUID, scopeKey: String, sent: SyncSentRevision) {
            self.id = id; self.libraryID = libraryID; self.scopeKey = scopeKey
            kind = sent.identity.kind.rawValue; entityID = sent.identity.id
            revision = sent.revision; packageID = sent.packageID
        }
    }
}

enum SyncStateMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SyncStateSchemaV1.self, SyncStateSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SyncStateSchemaV1.self, toVersion: SyncStateSchemaV2.self)] }
}
