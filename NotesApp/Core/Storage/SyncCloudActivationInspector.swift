import CloudKit
import CryptoKit

/// No configuration is bundled/enabled by this milestone. Call explicitly only
/// after configuring the real container and obtaining permission to inspect it.
struct SyncCloudActivationInspector: Sendable {
    private let transport: @Sendable (SyncCloudInspectionConfiguration) throws -> any SyncCloudInspectionTransport
    private let notifications: NotificationCenter

    init(notifications: NotificationCenter = .default,
         transport: @escaping @Sendable (SyncCloudInspectionConfiguration) throws -> any SyncCloudInspectionTransport = { try CloudKitInspectionTransport(configuration: $0) }) {
        self.transport = transport; self.notifications = notifications
    }

    func inspect(configuration: SyncCloudInspectionConfiguration?) async throws -> SyncRemoteBaseline {
        guard let configuration else { throw SyncActivationError.notConfigured }
        try configuration.validate(); try Task.checkCancellation()
        let watch = SyncAccountChangeWatch(center: notifications)
        let client = try transport(configuration)
        let account = try await client.accountRecordName()
        let scope = try SyncAccountScope(containerIdentifier: configuration.containerIdentifier,
            environment: configuration.environment, accountRecordName: account, zone: configuration.zoneID)
        var entities: [SyncEntityIdentity: SyncRemoteEntityHeader] = [:], blobs = Set<String>()
        var deleted = Set<SyncEntityIdentity>(), tokens = Set<Data>(), cursor: Data?
        for _ in 0..<2_000 {
            try Task.checkCancellation(); try watch.check()
            let page = try await client.page(after: cursor)
            guard !page.token.isEmpty, page.token.count <= 1_048_576 else { throw SyncActivationError.incompleteBaseline }
            let digest = Data(SHA256.hash(data: page.token))
            if !tokens.insert(digest).inserted {
                // An empty final tail may legitimately retain the immediately prior cursor.
                guard !page.moreComing, page.modifications.isEmpty, page.deletions.isEmpty,
                      cursor.map({ Data(SHA256.hash(data: $0)) }) == digest else { throw SyncActivationError.incompleteBaseline }
            }
            let modificationNames = Set(page.modifications.map(\.name)), deletionNames = Set(page.deletions.map(\.name))
            guard modificationNames.count == page.modifications.count, deletionNames.count == page.deletions.count,
                  modificationNames.isDisjoint(with: deletionNames) else { throw SyncActivationError.incompleteBaseline }
            for header in page.modifications {
                try header.validate()
                switch header {
                case .entity(let entity): entities[entity.identity] = entity; deleted.remove(entity.identity)
                case .blob(let name, _): blobs.insert(name)
                }
            }
            for deletion in page.deletions {
                switch deletion.recordType {
                case SyncCloudRecordPlan.entityType:
                    let identity = try SyncRemoteHeader.identity(deletion.name)
                    entities.removeValue(forKey: identity); deleted.insert(identity)
                case SyncCloudRecordPlan.blobType:
                    guard deletion.name.hasPrefix("blob."), SyncRemoteHeader.validHash(String(deletion.name.dropFirst(5))) else { throw SyncActivationError.unsupportedRecord }
                    blobs.remove(deletion.name)
                default: throw SyncActivationError.unsupportedRecord
                }
            }
            guard entities.count + blobs.count + deleted.count <= 400_000 else { throw SyncActivationError.tooLarge }
            cursor = page.token
            if !page.moreComing {
                guard try await client.accountRecordName() == account else { throw SyncActivationError.accountChanged }
                try watch.check(); try Task.checkCancellation()
                return SyncRemoteBaseline(id: UUID(), scope: scope, entities: entities, blobNames: blobs,
                    deletedEntities: deleted, finalToken: page.token)
            }
        }
        throw SyncActivationError.tooLarge
    }
}

/// Notification callbacks may arrive on any thread; only the locked flag is shared.
private final class SyncAccountChangeWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?
    init(center: NotificationCenter) {
        self.center = center
        observer = center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }; self.lock.withLock { self.changed = true }
        }
    }
    func check() throws { if lock.withLock({ changed }) { throw SyncActivationError.accountChanged } }
    deinit { if let observer { center.removeObserver(observer) } }
}
