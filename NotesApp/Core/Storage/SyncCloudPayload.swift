import Foundation

/// Wire format v1. File-valued metadata fields contain blob record names, never
/// local paths. A future receiver must resolve them before installing local models.
struct SyncCloudPayload: Codable, Sendable {
    let version: Int
    let identity: SyncEntityIdentity
    let revision: UUID
    let metadata: Data
    let assets: [Asset]

    struct Asset: Codable, Sendable {
        let role: String
        let recordName: String
        let sha256: String
        let byteCount: UInt64
    }

    /// Input must have passed staging.load integrity checks on the staging actor.
    static func make(from package: PreparedSyncUpload) throws -> Self {
        guard package.manifest.operation == .upsert, let url = package.metadataURL else {
            throw SyncCloudError.invalidMetadata
        }
        let data = try Data(contentsOf: url)
        let assets = package.manifest.assets.sorted { $0.role < $1.role }.map {
            Asset(role: $0.role, recordName: "blob.\($0.sha256)", sha256: $0.sha256, byteCount: $0.byteCount)
        }
        let byRole = Dictionary(uniqueKeysWithValues: assets.map { ($0.role, $0.recordName) })
        var used = Set<String>()
        func asset(_ role: String, required: Bool) throws -> String? {
            guard let name = byRole[role] else {
                if required { throw SyncUploadError.missingAsset(role) }
                return nil
            }
            used.insert(role); return name
        }
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func encode<T: Encodable>(_ value: T, id: UUID) throws -> Data {
            guard id == package.manifest.identity.id else { throw SyncCloudError.invalidMetadata }
            return try encoder.encode(value)
        }
        let metadata: Data
        switch package.manifest.identity.kind {
        case .folder:
            let value = try decoder.decode(BackupManifest.SavedFolder.self, from: data)
            guard value.parentID != value.id else { throw SyncCloudError.invalidMetadata }
            metadata = try encode(value, id: value.id)
        case .notebook:
            let value = try decoder.decode(BackupManifest.SavedNotebook.self, from: data)
            metadata = try encode(value, id: value.id)
        case .section:
            let value = try decoder.decode(BackupManifest.SavedSection.self, from: data)
            guard value.sortIndex >= 0 else { throw SyncCloudError.invalidMetadata }
            metadata = try encode(value, id: value.id)
        case .page:
            var value = try decoder.decode(BackupManifest.SavedPage.self, from: data)
            guard value.notebookID != nil, value.index >= 0,
                  value.pdfIndex.map({ $0 >= 0 }) ?? true,
                  [value.width, value.height].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 14400 }),
                  value.margin.map({ $0.isFinite && $0 >= 0 && $0 + (value.width ?? 768) <= 14400 }) ?? true
            else { throw SyncCloudError.invalidMetadata }
            value.drawing = try asset("drawing", required: value.drawing != nil)
            if value.pdf != nil { value.pdf = try asset("pdf", required: true) }
            var objects = try PageElementsCodec.decode(value.objects)
            for index in objects.indices {
                let suffix = objects[index].id.uuidString.lowercased()
                if objects[index].imagePath != nil {
                    objects[index].imagePath = try asset("image.\(suffix)", required: true)
                }
                if objects[index].fontFilePath != nil {
                    objects[index].fontFilePath = try asset("font.\(suffix)", required: true)
                }
            }
            if value.objects != nil { value.objects = try PageElementsCodec.encode(objects) }
            metadata = try encode(value, id: value.id)
        case .deck:
            let value = try decoder.decode(BackupManifest.SavedDeck.self, from: data)
            metadata = try encode(value, id: value.id)
        case .card:
            var value = try decoder.decode(BackupManifest.SavedCard.self, from: data)
            guard value.interval.isFinite, value.interval >= 0, value.repetitions >= 0, value.lapses >= 0 else {
                throw SyncCloudError.invalidMetadata
            }
            if value.questionImage != nil { value.questionImage = try asset("question", required: true) }
            if value.answerImage != nil { value.answerImage = try asset("answer", required: true) }
            metadata = try encode(value, id: value.id)
        case .review:
            let value = try decoder.decode(BackupManifest.SavedReview.self, from: data)
            guard value.interval.isFinite, value.interval >= 0 else { throw SyncCloudError.invalidMetadata }
            metadata = try encode(value, id: value.id)
        }
        guard used == Set(byRole.keys) else { throw SyncCloudError.invalidMetadata }
        return Self(version: 1, identity: package.manifest.identity, revision: package.manifest.revision,
                    metadata: metadata, assets: assets)
    }
}

enum SyncCloudError: LocalizedError {
    case invalidMetadata, invalidSystemFields, invalidZone, assetTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidMetadata: "This saved item cannot be converted to the current cloud format. Its local data and pending change are preserved."
        case .invalidSystemFields: "The saved cloud record metadata does not match this record. It has not been replaced."
        case .invalidZone: "Cloud records require an explicitly configured private custom zone."
        case .assetTooLarge: "A file exceeds the current cloud-preparation limit. Its local copy is unchanged."
        }
    }
}
