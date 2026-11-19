import Foundation
import SwiftData

/// Stable local identity; titles, positions and file locations never form a record identifier.
public enum SyncEntityKind: String, Codable, CaseIterable, Sendable {
    case folder, notebook, page, section, deck, card, review
}

public enum SyncChangeOperation: String, Codable, Sendable { case upsert, delete }

public struct SyncEntityIdentity: Hashable, Codable, Sendable {
    public let kind: SyncEntityKind
    public let id: UUID
    public var recordName: String { "\(kind.rawValue).\(id.uuidString.lowercased())" }
    public init(kind: SyncEntityKind, id: UUID) { self.kind = kind; self.id = id }
}

/// Device-local pending intent, committed with its user-data mutation. Contains no asset bytes.
/// A future CloudKit transport must enroll existing data and bind an account before sending.
@Model public final class SyncChange {
    @Attribute(.unique) public var recordName: String
    public var entityID: UUID
    public var kindRawValue: String
    public var operationRawValue: String
    public var revision: UUID
    public var changedAt: Date

    public init(identity: SyncEntityIdentity, operation: SyncChangeOperation, now: Date = .now) {
        recordName = identity.recordName; entityID = identity.id; kindRawValue = identity.kind.rawValue
        operationRawValue = operation.rawValue; revision = UUID(); changedAt = now
    }
}
