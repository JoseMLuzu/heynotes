import Foundation
import CryptoKit

/// App-owned durable packages live outside Documents and never share writable source paths.
/// No automatic purge: a future sender releases a package only after its operation finishes.
actor SyncUploadStagingStore {
    private let root: URL
    private var readPasses = 0
    private var sourceBytes: UInt64 = 0
    struct CopyStatistics: Sendable { let readPasses: Int; let sourceBytes: UInt64 }
    func statistics() -> CopyStatistics { CopyStatistics(readPasses: readPasses, sourceBytes: sourceBytes) }
    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("HeyNotesSyncUploads", isDirectory: true)) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func prepare(_ captured: CapturedSyncUpload) throws -> PreparedSyncUpload {
        guard captured.sources.count <= 256, (captured.plan.metadata?.count ?? 0) <= 64 * 1_048_576,
              captured.sources.keys.allSatisfy(Self.validRole),
              captured.plan.operation != .delete || (captured.sources.isEmpty && captured.plan.metadata == nil),
              captured.plan.operation != .upsert || captured.plan.metadata != nil else { throw SyncUploadError.invalidSnapshot }
        try prepareRoot(); try Task.checkCancellation()
        let id = UUID(), building = root.appendingPathComponent(".building-\(id.uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: building, withIntermediateDirectories: false)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: building) } }
        try owner(id).write(to: building.appendingPathComponent(".owner"), options: .atomic)
        var assets: [SyncStagedAsset] = []
        var copied: [ObjectIdentifier: SyncStagedAsset] = [:]
        for (role, file) in captured.sources.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            if let prior = copied[ObjectIdentifier(file)] {
                assets.append(SyncStagedAsset(role: role, sha256: prior.sha256, byteCount: prior.byteCount))
                continue
            }
            let temporary = building.appendingPathComponent(UUID().uuidString)
            let (digest, size) = try file.copy(to: temporary)
            readPasses += 1; sourceBytes &+= size
            let asset = SyncStagedAsset(role: role, sha256: digest, byteCount: size)
            let final = building.appendingPathComponent(asset.filename)
            if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: final); try makeReadOnly(final) }
            assets.append(asset)
            copied[ObjectIdentifier(file)] = asset
        }
        let metadataHash = captured.plan.metadata.map(Self.digest)
        if let metadata = captured.plan.metadata {
            let url = building.appendingPathComponent("metadata.json")
            try metadata.write(to: url, options: .atomic); try makeReadOnly(url)
        }
        let manifest = SyncUploadManifest(id: id, identity: captured.plan.identity, revision: captured.plan.revision,
            operation: captured.plan.operation, createdAt: .now, metadataSHA256: metadataHash, assets: assets)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let manifestURL = building.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic); try makeReadOnly(manifestURL)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: building, to: destination)
        published = true
        return PreparedSyncUpload(manifest: manifest, directory: destination)
    }

    /// Reopen/retry validates bytes and names. Corruption is reported, never silently deleted.
    func load(_ id: UUID) throws -> PreparedSyncUpload {
        try prepareRoot()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try checkLocation(directory, directory: true)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try checkLocation(manifestURL)
        guard try byteCount(manifestURL) <= 1_048_576 else { throw SyncUploadError.tooLarge }
        let manifest: SyncUploadManifest
        do { manifest = try JSONDecoder().decode(SyncUploadManifest.self, from: Data(contentsOf: manifestURL)) }
        catch { throw SyncUploadError.invalidSnapshot }
        guard manifest.formatVersion == 1, manifest.id == id, manifest.assets.count <= 256,
              Set(manifest.assets.map(\.role)).count == manifest.assets.count,
              manifest.operation != .delete || (manifest.assets.isEmpty && manifest.metadataSHA256 == nil),
              manifest.operation != .upsert || manifest.metadataSHA256 != nil else { throw SyncUploadError.invalidSnapshot }
        if let hash = manifest.metadataSHA256 {
            let metadata = directory.appendingPathComponent("metadata.json")
            try checkLocation(metadata)
            guard Self.validHash(hash), try byteCount(metadata) <= 64 * 1_048_576,
                  try Self.digest(Data(contentsOf: metadata)) == hash else { throw SyncUploadError.invalidSnapshot }
        }
        var verified = Set<String>()
        for asset in manifest.assets {
            guard Self.validHash(asset.sha256), Self.validRole(asset.role) else {
                throw SyncUploadError.invalidSnapshot
            }
            let url = directory.appendingPathComponent(asset.filename)
            try checkLocation(url)
            guard try byteCount(url) == asset.byteCount else { throw SyncUploadError.invalidSnapshot }
            if verified.insert(asset.sha256).inserted {
                guard try hashFile(url) == asset.sha256 else { throw SyncUploadError.invalidSnapshot }
            }
        }
        return PreparedSyncUpload(manifest: manifest, directory: directory)
    }

    func packageIDs() throws -> [UUID] {
        try prepareRoot()
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { UUID(uuidString: $0.lastPathComponent) }.sorted { $0.uuidString < $1.uuidString }
    }

    /// Call after the future CloudKit operation ends, or explicitly abandon an unused package.
    /// A UUID names only an owned package; no caller-supplied URL or original asset is removed.
    func discard(_ id: UUID) throws {
        try prepareRoot()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try checkLocation(directory, directory: true)
        let marker = directory.appendingPathComponent(".owner")
        try checkLocation(marker)
        guard try byteCount(marker) <= 128, try Data(contentsOf: marker) == owner(id) else { throw SyncUploadError.unsafePath }
        try FileManager.default.removeItem(at: directory)
    }

    private func prepareRoot() throws {
        guard root.resolvingSymlinksInPath().path == root.path else { throw SyncUploadError.unsafePath }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root, values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    private func checkLocation(_ url: URL, directory: Bool = false) throws {
        guard url.standardizedFileURL.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              url.path.hasPrefix(root.path + "/") else { throw SyncUploadError.unsafePath }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular) else {
            throw SyncUploadError.unsafePath
        }
    }
    private func makeReadOnly(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
    }
    private func owner(_ id: UUID) -> Data { Data("HeyNotesSyncUpload:1:\(id.uuidString)".utf8) }
    private func byteCount(_ url: URL) throws -> UInt64 {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else { throw SyncUploadError.invalidSnapshot }
        return size.uint64Value
    }
    private func hashFile(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            guard let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty else { break }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func validRole(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 80 && value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 45
        }
    }
}
