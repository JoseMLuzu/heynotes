import CloudKit

extension PreparedSyncUpload {
    /// Actual CKAsset objects backed by the prepared copies, never live drawing/PDF paths.
    /// These role keys are local identifiers, not a CloudKit record schema. No server access.
    func cloudAssets() -> [String: CKAsset] {
        Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.role, CKAsset(fileURL: assetURL($0))) })
    }
}
