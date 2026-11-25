import Foundation

enum SyncEnrollmentStatus: Sendable {
    case notStarted
    case preparing(UUID)
    case readyForRemoteReconciliation(SyncEnrollmentReport)
}

/// A point-in-time identity inventory, not a content snapshot or upload authorization.
struct SyncEnrollmentReport: Codable, Sendable {
    var version = 1
    let enrollmentID: UUID
    let libraryID: UUID
    let completedAt: Date
    let entityCounts: [String: Int]
    let enqueued: Int
    let preservedUpserts: Int
    let preservedDeletions: Int
    let identityDigest: String
    var entityCount: Int { entityCounts.values.reduce(0, +) }

    func validate() throws {
        let limit = SyncInitialEnrollmentStore.maximumIdentities
        guard version == 1, Set(entityCounts.keys) == Set(SyncEntityKind.allCases.map(\.rawValue)),
              entityCounts.values.allSatisfy({ (0...limit).contains($0) }), entityCount <= limit,
              (0...limit).contains(enqueued), (0...limit).contains(preservedUpserts),
              enqueued + preservedUpserts == entityCount, (0...limit).contains(preservedDeletions),
              entityCount + preservedDeletions <= limit, identityDigest.utf8.count == 64,
              identityDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SyncEnrollmentError.invalidInventory
        }
    }
}

enum SyncEnrollmentError: LocalizedError, Equatable {
    case pending, inconsistentJournal, tooLarge, invalidInventory, existingCheckpoint
    var errorDescription: String? {
        switch self {
        case .pending: "Initial library preparation must finish before processing cloud results."
        case .inconsistentJournal: "A pending change does not match the saved library. Nothing was replaced or removed."
        case .tooLarge: "This library exceeds the current initial-preparation limit. Its notes and pending changes are preserved."
        case .invalidInventory: "The saved initial-preparation report could not be verified. It has been retained."
        case .existingCheckpoint: "This library already has an engine checkpoint. Reconcile its existing sync state before initial enrollment."
        }
    }
}
