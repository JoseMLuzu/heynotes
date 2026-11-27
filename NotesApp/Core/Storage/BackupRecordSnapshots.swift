import Foundation

// One value mapping for editable backups and private local upload snapshots. Models stay on
// their context's executor; only these Codable/Sendable values leave the metadata actor.
extension BackupManifest.SavedFolder {
    init(_ value: Folder) {
        self.init(id: value.id, title: value.title, createdAt: value.createdAt, color: value.colorRawValue,
                  favorite: value.isFavorite, trashedAt: value.trashedAt, parentID: value.parent?.id)
    }
}
extension BackupManifest.SavedNotebook {
    init(_ value: Notebook) {
        self.init(id: value.id, title: value.title, createdAt: value.createdAt, updatedAt: value.updatedAt,
                  cover: value.coverColorRawValue, trashedAt: value.trashedAt, favorite: value.isFavorite, folderID: value.folder?.id)
    }
}
extension BackupManifest.SavedSection {
    init(_ value: NotebookSection) {
        self.init(id: value.id, title: value.title, sortIndex: value.sortIndex, notebookID: value.notebook?.id)
    }
}
extension BackupManifest.SavedPage {
    init(_ value: NotePage) {
        self.init(id: value.id, notebookID: value.notebook?.id, sectionID: value.section?.id, index: value.pageIndex,
                  template: value.paperTemplateRawValue, drawing: value.drawingFilePath, pdf: value.pdfFilePath,
                  pdfIndex: value.pdfPageIndex, width: value.pageWidth, height: value.pageHeight,
                  bookmark: value.bookmarkTitle, objects: value.objectsData, margin: value.pdfRightMargin,
                  createdAt: value.createdAt, updatedAt: value.updatedAt, trashedAt: value.trashedAt)
    }
}
extension BackupManifest.SavedDeck {
    init(_ value: StudyDeck) {
        self.init(id: value.id, title: value.title, notebookID: value.notebookID, createdAt: value.createdAt, trashedAt: value.trashedAt)
    }
}
extension BackupManifest.SavedCard {
    init(_ value: Flashcard) {
        self.init(id: value.id, deckID: value.deck?.id, question: value.question, answer: value.answer,
                  sourceNotebookID: value.sourceNotebookID, sourcePageID: value.sourcePageID, createdAt: value.createdAt,
                  updatedAt: value.updatedAt, trashedAt: value.trashedAt, nextReviewAt: value.nextReviewAt,
                  interval: value.intervalSeconds, repetitions: value.repetitionCount, lapses: value.lapseCount,
                  questionImage: value.questionImagePath, answerImage: value.answerImagePath)
    }
}
extension BackupManifest.SavedReview {
    init(_ value: ReviewRecord) {
        self.init(id: value.id, cardID: value.flashcard?.id, reviewedAt: value.reviewedAt, rating: value.ratingRawValue,
                  nextReviewAt: value.nextReviewAt, interval: value.intervalSeconds, schedulerVersion: value.schedulerVersion)
    }
}
