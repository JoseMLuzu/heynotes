import Foundation

/// Portable library records, independent of the SQLite store and SwiftData schema internals.
struct BackupManifest: Codable, Sendable {
    var formatVersion = 3
    var createdAt = Date.now
    var folders: [SavedFolder]
    var notebooks: [SavedNotebook]
    var sections: [SavedSection]
    var pages: [SavedPage]
    var decks: [SavedDeck]
    var cards: [SavedCard]
    var reviews: [SavedReview]

    struct SavedFolder: Codable, Sendable {
        var id: UUID; var title: String; var createdAt: Date; var color: String?
        var favorite: Bool; var trashedAt: Date?; var parentID: UUID?
    }
    struct SavedNotebook: Codable, Sendable {
        var id: UUID; var title: String; var createdAt: Date; var updatedAt: Date
        var cover: String; var trashedAt: Date?; var favorite: Bool; var folderID: UUID?
    }
    struct SavedSection: Codable, Sendable {
        var id: UUID; var title: String; var sortIndex: Int; var notebookID: UUID?
    }
    struct SavedPage: Codable, Sendable {
        var id: UUID; var notebookID: UUID?; var sectionID: UUID?; var index: Int; var template: String
        var drawing: String?; var pdf: String?; var pdfIndex: Int?
        var width: Double?; var height: Double?; var bookmark: String?; var objects: Data?; var margin: Double?
        var createdAt: Date; var updatedAt: Date
        var trashedAt: Date? = nil
    }
    struct SavedDeck: Codable, Sendable {
        var id: UUID; var title: String; var notebookID: UUID?; var createdAt: Date; var trashedAt: Date?
    }
    struct SavedCard: Codable, Sendable {
        var id: UUID; var deckID: UUID?; var question: String; var answer: String
        var sourceNotebookID: UUID?; var sourcePageID: UUID?; var createdAt: Date; var updatedAt: Date
        var trashedAt: Date?; var nextReviewAt: Date; var interval: Double; var repetitions: Int; var lapses: Int
        var questionImage: String? = nil; var answerImage: String? = nil
    }
    struct SavedReview: Codable, Sendable {
        var id: UUID; var cardID: UUID?; var reviewedAt: Date; var rating: String
        var nextReviewAt: Date; var interval: Double; var schedulerVersion: Int
    }
}

struct BackupFile: Sendable {
    let path: String
    let size: UInt64
    let digest: Data
}

struct PreparedLibraryBackup: Identifiable, Sendable {
    let id: UUID
    let directory: URL
    let manifest: BackupManifest
    let files: [BackupFile]
    var byteCount: UInt64 { files.reduce(0) { $0 + $1.size } }
}

enum LibraryBackupError: LocalizedError {
    case invalidArchive, unsupportedVersion, invalidMetadata, unsafePath, missingFile(String), changedFile
    case integrity, tooLarge, savePending, busy
    var errorDescription: String? {
        switch self {
        case .invalidArchive: "This is not a complete HeyNotes backup. Choose another file."
        case .unsupportedVersion: "This backup uses a newer format. Update HeyNotes before restoring it."
        case .invalidMetadata: "The backup's library relationships or page content are invalid. Nothing was restored."
        case .unsafePath: "The backup contains an unsupported file path. Nothing was restored."
        case .missingFile(let path): "A library file is missing: \(path). Recover it before creating a complete backup."
        case .changedFile: "A file changed while preparing the backup. Please try again."
        case .integrity: "The backup failed its integrity check. Nothing was restored."
        case .tooLarge: "The backup metadata exceeds the supported size. Its original file is unchanged."
        case .savePending: "Your latest handwriting could not be saved. Resolve the save error before backing up."
        case .busy: "Finish the current document operation, then try again."
        }
    }
}
