import Foundation

struct SyncActivationLocalInventory: Sendable {
    struct Pending: Sendable { let operation: SyncChangeOperation; let revision: UUID }
    let libraryID: UUID
    let identities: Set<SyncEntityIdentity>
    let pending: [SyncEntityIdentity: Pending]
    var fingerprint: String {
        SyncIdentityInventory.digest(identities.map { "live:" + $0.recordName } + pending.map {
            "pending:\($0.key.recordName):\($0.value.operation.rawValue):\($0.value.revision.uuidString)"
        })
    }
}

/// Advisory reconciliation review only. No operation in this type enables a sender,
/// acknowledges a journal row, merges ink or deletes either library's content.
struct SyncActivationReview: Sendable {
    enum Disposition: String, Sendable {
        case localOnlyNeedsReview, remoteOnlyNeedsDownload, sharedIdentityNeedsComparison
        case localDeletionNeedsReview, remoteDeletionNeedsReview
    }
    struct Item: Sendable { let identity: SyncEntityIdentity; let disposition: Disposition }
    let id: UUID
    let libraryID: UUID
    let enrollmentID: UUID
    let leaseGeneration: UUID
    let scopeKey: String
    let localFingerprint: String
    let remoteBaselineID: UUID
    let remoteFingerprint: String
    let items: [Item]

    static func make(local: SyncActivationLocalInventory, remote: SyncRemoteBaseline,
                     enrollmentID: UUID, lease: SyncStateLease) throws -> Self {
        try remote.validate()
        guard local.libraryID == lease.libraryID, remote.scope == lease.scope else { throw SyncActivationError.scopeMismatch }
        let all = local.identities.union(local.pending.keys).union(remote.entities.keys).union(remote.deletedEntities)
        let items = all.sorted { $0.recordName < $1.recordName }.map { identity -> Item in
            let disposition: Disposition
            if local.pending[identity]?.operation == .delete { disposition = .localDeletionNeedsReview }
            else if remote.entities[identity]?.deleted == true || remote.deletedEntities.contains(identity) { disposition = .remoteDeletionNeedsReview }
            else if local.identities.contains(identity), remote.entities[identity] != nil { disposition = .sharedIdentityNeedsComparison }
            else if local.identities.contains(identity) { disposition = .localOnlyNeedsReview }
            else { disposition = .remoteOnlyNeedsDownload }
            return Item(identity: identity, disposition: disposition)
        }
        return Self(id: UUID(), libraryID: local.libraryID, enrollmentID: enrollmentID, leaseGeneration: lease.generation,
            scopeKey: lease.key, localFingerprint: local.fingerprint, remoteBaselineID: remote.id, remoteFingerprint: remote.fingerprint, items: items)
    }

    func validate(local: SyncActivationLocalInventory, remote: SyncRemoteBaseline, lease: SyncStateLease) throws {
        try remote.validate()
        guard libraryID == lease.libraryID, scopeKey == lease.key, leaseGeneration == lease.generation,
              local.libraryID == libraryID, local.fingerprint == localFingerprint,
              remote.scope == lease.scope, remote.id == remoteBaselineID, remote.fingerprint == remoteFingerprint else { throw SyncActivationError.staleReview }
    }
}

enum SyncActivationError: LocalizedError, Equatable {
    case notConfigured, invalidConfiguration, accountUnavailable, accountChanged, scopeMismatch
    case unsupportedRecord, incompleteBaseline, tooLarge, staleReview, enrollmentRequired
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud inspection requires a configured development container. Nothing was uploaded."
        case .invalidConfiguration: "The cloud container and custom-zone configuration are invalid."
        case .accountUnavailable: "An available iCloud account is required before reviewing this library."
        case .accountChanged: "The iCloud account changed during inspection. Review the active account again."
        case .scopeMismatch: "This cloud inventory belongs to a different account or scope."
        case .unsupportedRecord: "The cloud zone contains unsupported or incomplete record metadata. Review cannot continue safely."
        case .incompleteBaseline: "The complete cloud inventory could not be verified. No activation was approved."
        case .tooLarge: "This account exceeds the current cloud-inspection limits. Its content is unchanged."
        case .staleReview: "The library or sync session changed. Refresh the activation review."
        case .enrollmentRequired: "Prepare the initial local library before reviewing cloud activation."
        }
    }
}
