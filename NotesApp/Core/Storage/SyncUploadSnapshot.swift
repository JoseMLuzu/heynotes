import Foundation

/// Private local snapshot, not a CloudKit wire record. A future mapper must replace local paths.
struct SyncUploadPlan: Sendable {
    let identity: SyncEntityIdentity
    let revision: UUID
    let operation: SyncChangeOperation
    let metadata: Data?
    let sources: [SyncAssetSource]
}

struct SyncAssetSource: Sendable {
    let role: String
    let path: String
    var allowsMissing = false // Only an unsaved blank page's deterministic drawing path.
}

struct CapturedSyncUpload: Sendable {
    let plan: SyncUploadPlan
    let sources: [String: SyncSourceFile]
}

struct SyncUploadManifest: Codable, Sendable {
    var formatVersion = 1
    let id: UUID
    let identity: SyncEntityIdentity
    let revision: UUID
    let operation: SyncChangeOperation
    let createdAt: Date
    let metadataSHA256: String?
    let assets: [SyncStagedAsset]
}

struct SyncStagedAsset: Codable, Sendable {
    let role: String
    let sha256: String
    let byteCount: UInt64
    var filename: String { sha256 + ".asset" }
}

struct PreparedSyncUpload: Sendable {
    let manifest: SyncUploadManifest
    let directory: URL

    var metadataURL: URL? {
        manifest.metadataSHA256 == nil ? nil : directory.appendingPathComponent("metadata.json")
    }
    func assetURL(_ asset: SyncStagedAsset) -> URL { directory.appendingPathComponent(asset.filename) }
}

enum SyncUploadError: LocalizedError {
    case unavailableRevision, missingEntity, missingAsset(String), invalidSnapshot, changedSource, unsafePath, tooLarge
    var errorDescription: String? {
        switch self {
        case .unavailableRevision: "This local revision is no longer pending. Prepare the latest version instead."
        case .missingEntity: "The pending item is unavailable. Its local change has been preserved."
        case .missingAsset(let role): "A required file is missing for \(role). The pending change has been preserved."
        case .invalidSnapshot: "This prepared upload is incomplete or damaged. Its files have been retained."
        case .changedSource: "A source file changed while being copied. Prepare the saved revision again."
        case .unsafePath: "The upload preparation contains an unsupported file location."
        case .tooLarge: "This item exceeds the current upload-preparation limits. Its original files are unchanged."
        }
    }
}
