import CloudKit

/// Durable reception only. No user ModelContext, engine checkpoint or upload acknowledgement.
actor SyncIncomingStore {
    enum Progress: Sendable { case manifestSaved, fileSaved(String), beforePublish, published }
    struct Inventory: Sendable { let received: [UUID]; let interrupted: [UUID] }
    private struct Binding: Codable { var version = 1; let libraryID: UUID; let scope: SyncAccountScope }
    private let directory: SyncStateDirectory
    private let libraryID: UUID
    private let scope: SyncAccountScope
    private let progress: @Sendable (Progress) throws -> Void
    private var closed = false

    init(directory url: URL = URL.applicationSupportDirectory.appendingPathComponent("HeyNotesSyncIncoming", isDirectory: true),
         libraryID: UUID, scope: SyncAccountScope,
         progress: @escaping @Sendable (Progress) throws -> Void = { _ in }) throws {
        try scope.validate()
        let directory = try SyncStateDirectory(url)
        let bindingURL = directory.url.appendingPathComponent("binding.json")
        do {
            if try SyncIncomingFiles.exists(bindingURL) {
                let binding = try SyncIncomingFiles.read(Binding.self, from: bindingURL)
                guard binding.version == 1, binding.libraryID == libraryID, binding.scope == scope else { throw SyncIncomingError.scopeMismatch }
            } else {
                guard try FileManager.default.contentsOfDirectory(atPath: directory.url.path).allSatisfy({ $0 == "writer.lock" }) else {
                    throw SyncIncomingError.integrity
                }
                try SyncIncomingFiles.write(Binding(libraryID: libraryID, scope: scope), to: bindingURL)
            }
        } catch { directory.release(); throw error }
        self.directory = directory; self.libraryID = libraryID; self.scope = scope; self.progress = progress
    }

    /// Future CloudKit delegate entry: copy CKAsset files before returning from its callback.
    func receive(fetched records: [CKRecord], deletions: [CKDatabase.RecordZoneChange.Deletion] = [],
                 deliveryID: UUID) throws -> SyncIncomingReceipt {
        try checkOpen()
        guard records.count + deletions.count <= 200 else { throw SyncIncomingError.tooLarge }
        let inputs = try records.map { try SyncIncomingInput(fetched: $0, scope: scope) }
        let removed = try deletions.map { value in
            guard value.recordID.zoneID == scope.zoneID else { throw SyncIncomingError.scopeMismatch }
            return SyncIncomingDeletion(name: value.recordID.recordName, type: value.recordType)
        }
        return try receive(inputs, deletions: removed, deliveryID: deliveryID)
    }

    /// The normalized-value seam also permits offline transport/domain tests. No success here
    /// claims that Apple sent these values or authorizes overwriting a local model.
    func receive(_ inputs: [SyncIncomingInput], deletions: [SyncIncomingDeletion] = [],
                 deliveryID: UUID) throws -> SyncIncomingReceipt {
        try checkOpen()
        let manifest = SyncIncomingManifest(id: deliveryID, libraryID: libraryID, scopeKey: scope.key,
            records: inputs.map(\.record).sorted { $0.name < $1.name }, deletions: deletions.sorted { $0.name < $1.name })
        try manifest.validate(libraryID: libraryID, scope: scope)
        let destination = folder(deliveryID, complete: true)
        if try SyncIncomingFiles.exists(destination) {
            let existing = try verifiedManifest(deliveryID)
            guard try existing.fingerprint == manifest.fingerprint else { throw SyncIncomingError.deliveryMismatch }
            return receipt(existing)
        }
        let staging = folder(deliveryID, complete: false)
        if try SyncIncomingFiles.exists(staging) {
            let prior = try readManifest(in: staging)
            guard try prior.fingerprint == manifest.fingerprint else { throw SyncIncomingError.deliveryMismatch }
        } else {
            let prior = try inventory()
            guard prior.received.count + prior.interrupted.count < 10_000 else { throw SyncIncomingError.tooLarge }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try SyncIncomingFiles.write(manifest, to: staging.appendingPathComponent("manifest.json"))
            try SyncIncomingFiles.syncDirectory(directory.url)
        }
        try progress(.manifestSaved)
        for input in inputs {
            try Task.checkCancellation()
            guard let filename = input.record.filename, let hash = input.record.sha256,
                  let bytes = input.record.byteCount else { continue }
            guard let source = input.source else { throw SyncIncomingError.missingAsset }
            try SyncIncomingFiles.install(source, as: staging.appendingPathComponent(filename), hash: hash, bytes: bytes)
            try progress(.fileSaved(input.record.name))
        }
        return try publish(deliveryID)
    }

    /// Resume an interrupted delivery whose complete bytes were already copied. Missing or
    /// damaged bytes remain retained and require refetch; they never become ready placeholders.
    func resume(_ deliveryID: UUID) throws -> SyncIncomingReceipt {
        try checkOpen()
        if try SyncIncomingFiles.exists(folder(deliveryID, complete: true)) { return receipt(try verifiedManifest(deliveryID)) }
        return try publish(deliveryID)
    }

    func inventory() throws -> Inventory {
        try checkOpen()
        let urls = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        guard urls.count <= 20_002 else { throw SyncIncomingError.tooLarge }
        var received: [UUID] = [], interrupted: [UUID] = []
        for url in urls {
            if let id = UUID(uuidString: url.lastPathComponent) { try SyncIncomingFiles.check(url, directory: true); received.append(id) }
            else if url.lastPathComponent.hasPrefix("receiving-"), let id = UUID(uuidString: String(url.lastPathComponent.dropFirst(10))) {
                try SyncIncomingFiles.check(url, directory: true); interrupted.append(id)
            }
        }
        guard Set(received).isDisjoint(with: interrupted) else { throw SyncIncomingError.integrity }
        return Inventory(received: received.sorted { $0.uuidString < $1.uuidString }, interrupted: interrupted.sorted { $0.uuidString < $1.uuidString })
    }

    func load(_ deliveryID: UUID) throws -> SyncIncomingManifest { try checkOpen(); return try verifiedManifest(deliveryID) }

    /// Resolves an immutable revision, not "latest server state". Blob arrivals can belong to
    /// another already published delivery. Conflicts/deletions still require a later importer.
    func entity(_ name: String, in deliveryID: UUID) throws -> SyncReceivedEntity {
        try checkOpen()
        let manifest = try verifiedManifest(deliveryID)
        guard let record = manifest.records.first(where: { $0.name == name && $0.type == SyncCloudRecordPlan.entityType }) else { throw SyncIncomingError.invalidRecord }
        guard !record.tombstone else { return .init(record: record, payload: nil, assetFiles: [:]) }
        let payload = try payload(record, directory: folder(deliveryID, complete: true))
        let deliveries = try inventory().received
        var locations: [String: URL] = [:], verified: [String: URL] = [:]
        for asset in payload.assets {
            if let prior = verified[asset.recordName] { locations[asset.role] = prior; continue }
            var found: URL?
            for id in deliveries {
                let location = folder(id, complete: true), candidate = try readManifest(in: location)
                if let blob = candidate.records.first(where: { $0.name == asset.recordName && $0.type == SyncCloudRecordPlan.blobType }) {
                    guard blob.byteCount == asset.byteCount, let filename = blob.filename else { throw SyncIncomingError.integrity }
                    let url = location.appendingPathComponent(filename)
                    try SyncIncomingFiles.verify(url, hash: asset.sha256, bytes: asset.byteCount)
                    found = url; break
                }
            }
            guard let found else { throw SyncIncomingError.missingAsset }
            verified[asset.recordName] = found; locations[asset.role] = found
        }
        return .init(record: record, payload: payload, assetFiles: locations)
    }

    func close() { closed = true; directory.release() }

    private func folder(_ id: UUID, complete: Bool) -> URL {
        directory.url.appendingPathComponent((complete ? "" : "receiving-") + id.uuidString, isDirectory: true)
    }
    private func checkOpen() throws { guard !closed else { throw SyncIncomingError.closed }; try Task.checkCancellation() }
    private func readManifest(in location: URL) throws -> SyncIncomingManifest {
        try SyncIncomingFiles.check(location, directory: true)
        let url = location.appendingPathComponent("manifest.json")
        guard try SyncIncomingFiles.exists(url) else { throw SyncIncomingError.incomplete }
        let manifest = try SyncIncomingFiles.read(SyncIncomingManifest.self, from: url)
        try manifest.validate(libraryID: libraryID, scope: scope)
        guard location.lastPathComponent == manifest.id.uuidString || location.lastPathComponent == "receiving-" + manifest.id.uuidString else { throw SyncIncomingError.integrity }
        return manifest
    }
    private func verifiedManifest(_ id: UUID) throws -> SyncIncomingManifest {
        let location = folder(id, complete: true), manifest = try readManifest(in: location)
        try verify(manifest, directory: location)
        return manifest
    }
    private func verify(_ manifest: SyncIncomingManifest, directory: URL) throws {
        var verified = Set<String>()
        for record in manifest.records {
            try Task.checkCancellation()
            if let filename = record.filename, let hash = record.sha256, let bytes = record.byteCount, verified.insert(filename).inserted {
                let url = directory.appendingPathComponent(filename)
                guard try SyncIncomingFiles.exists(url) else { throw SyncIncomingError.incomplete }
                try SyncIncomingFiles.verify(url, hash: hash, bytes: bytes)
            }
            if record.type == SyncCloudRecordPlan.entityType, !record.tombstone { _ = try payload(record, directory: directory) }
        }
    }
    private func payload(_ record: SyncIncomingRecord, directory: URL) throws -> SyncCloudPayload {
        guard let filename = record.filename else { throw SyncIncomingError.invalidRecord }
        let data = try SyncIncomingFiles.read(directory.appendingPathComponent(filename), maximum: SyncCloudRecordPlan.maximumAssetBytes)
        let value = try JSONDecoder().decode(SyncCloudPayload.self, from: data)
        try SyncIncomingPayloadValidation.validate(value, for: record)
        return value
    }
    private func publish(_ id: UUID) throws -> SyncIncomingReceipt {
        let staging = folder(id, complete: false), manifest = try readManifest(in: staging)
        try verify(manifest, directory: staging)
        try progress(.beforePublish); try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: folder(id, complete: true))
        try SyncIncomingFiles.syncDirectory(directory.url)
        try progress(.published)
        return receipt(manifest)
    }
    private func receipt(_ manifest: SyncIncomingManifest) -> SyncIncomingReceipt {
        .init(deliveryID: manifest.id, libraryID: libraryID, scopeKey: scope.key,
              recordCount: manifest.records.count, deletionCount: manifest.deletions.count)
    }
}
