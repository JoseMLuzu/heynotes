import Foundation

/// Validates wire metadata without creating SwiftData objects or resolving relationships.
/// Parent availability and local/remote conflicts belong to the later apply transaction.
enum SyncIncomingPayloadValidation {
    static func validate(_ payload: SyncCloudPayload, for record: SyncIncomingRecord) throws {
        let identity = try SyncRemoteHeader.identity(record.name)
        guard payload.version == 1, payload.identity == identity, payload.revision == record.revision,
              payload.assets.count <= 256, payload.metadata.count <= SyncCloudRecordPlan.maximumAssetBytes,
              Set(payload.assets.map(\.role)).count == payload.assets.count else { throw SyncIncomingError.invalidRecord }
        var byRole: [String: SyncCloudPayload.Asset] = [:], sizes: [String: UInt64] = [:]
        for asset in payload.assets {
            guard !asset.role.isEmpty, asset.role.utf8.count <= 80,
                  asset.role.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) || [45, 46].contains($0) }),
                  SyncRemoteHeader.validHash(asset.sha256), asset.recordName == "blob." + asset.sha256,
                  asset.byteCount <= SyncCloudRecordPlan.maximumAssetBytes else { throw SyncIncomingError.invalidRecord }
            if let prior = sizes[asset.recordName], prior != asset.byteCount { throw SyncIncomingError.integrity }
            sizes[asset.recordName] = asset.byteCount; byRole[asset.role] = asset
        }
        guard Set(sizes.keys) == Set(record.blobs) else { throw SyncIncomingError.invalidRecord }
        var used = Set<String>()
        func reference(_ role: String, _ name: String?) throws {
            guard let name else {
                guard byRole[role] == nil else { throw SyncIncomingError.invalidRecord }
                return
            }
            guard let asset = byRole[role], name == asset.recordName else { throw SyncIncomingError.invalidRecord }
            used.insert(role)
        }
        func sameID(_ id: UUID) throws { guard id == identity.id else { throw SyncIncomingError.invalidRecord } }
        func dates(_ values: Date?...) throws {
            guard values.compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { throw SyncIncomingError.invalidRecord }
        }
        let decoder = JSONDecoder()
        switch identity.kind {
        case .folder:
            let value = try decoder.decode(BackupManifest.SavedFolder.self, from: payload.metadata)
            try sameID(value.id); try dates(value.createdAt, value.trashedAt)
            guard value.parentID != value.id else { throw SyncIncomingError.invalidRecord }
        case .notebook:
            let value = try decoder.decode(BackupManifest.SavedNotebook.self, from: payload.metadata)
            try sameID(value.id); try dates(value.createdAt, value.updatedAt, value.trashedAt)
        case .section:
            let value = try decoder.decode(BackupManifest.SavedSection.self, from: payload.metadata)
            try sameID(value.id)
            guard value.sortIndex >= 0 else { throw SyncIncomingError.invalidRecord }
        case .page:
            let value = try decoder.decode(BackupManifest.SavedPage.self, from: payload.metadata)
            try sameID(value.id); try dates(value.createdAt, value.updatedAt, value.trashedAt)
            guard value.notebookID != nil, value.index >= 0, PaperTemplate(rawValue: value.template) != nil,
                  [value.width, value.height].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 14400 }),
                  value.margin.map({ $0.isFinite && $0 >= 0 && $0 + (value.width ?? 768) <= 14400 }) ?? true,
                  (value.pdf == nil && value.pdfIndex == nil) || (value.pdf != nil && value.pdfIndex.map({ $0 >= 0 }) == true)
            else { throw SyncIncomingError.invalidRecord }
            try reference("drawing", value.drawing); try reference("pdf", value.pdf)
            for item in try PageElementsCodec.decode(value.objects) {
                let suffix = item.id.uuidString.lowercased()
                try reference("image." + suffix, item.imagePath)
                try reference("font." + suffix, item.fontFilePath)
            }
        case .deck:
            let value = try decoder.decode(BackupManifest.SavedDeck.self, from: payload.metadata)
            try sameID(value.id); try dates(value.createdAt, value.trashedAt)
        case .card:
            let value = try decoder.decode(BackupManifest.SavedCard.self, from: payload.metadata)
            try sameID(value.id); try dates(value.createdAt, value.updatedAt, value.trashedAt, value.nextReviewAt)
            guard value.interval.isFinite, value.interval >= 0, value.repetitions >= 0, value.lapses >= 0 else { throw SyncIncomingError.invalidRecord }
            try reference("question", value.questionImage); try reference("answer", value.answerImage)
        case .review:
            let value = try decoder.decode(BackupManifest.SavedReview.self, from: payload.metadata)
            try sameID(value.id); try dates(value.reviewedAt, value.nextReviewAt)
            guard value.interval.isFinite, value.interval >= 0,
                  ReviewRating(rawValue: value.rating) != nil, value.schedulerVersion >= 1 else { throw SyncIncomingError.invalidRecord }
        }
        guard used == Set(byRole.keys) else { throw SyncIncomingError.invalidRecord }
    }
}
