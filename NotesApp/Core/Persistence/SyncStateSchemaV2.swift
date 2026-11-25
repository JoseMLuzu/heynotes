import Foundation
import SwiftData

/// V1 is frozen. Only the sidecar Library adds optional enrollment progress fields.
enum SyncStateSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Library.self, SyncStateSchemaV1.Record.self, SyncStateSchemaV1.Receipt.self]
    }

    @Model final class Library {
        @Attribute(.unique) var localName: String
        @Attribute(.unique) var id: UUID
        var scopeData: Data?
        var scopeKey: String?
        var activeGeneration: UUID?
        var engineData: Data?
        var engineSequence: Int64
        var enrollmentID: UUID? = nil
        var enrollmentStartedAt: Date? = nil
        var enrollmentReport: Data? = nil
        init(localName: String) {
            self.localName = localName; id = UUID(); engineSequence = 0
        }
    }
}
