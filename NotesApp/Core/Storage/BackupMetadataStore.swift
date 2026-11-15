import Foundation
import SwiftData

/// Constructed on the backup service's executor; model objects never leave this actor.
@ModelActor actor BackupMetadataStore {
    func capture() throws -> BackupManifest {
        modelContext.autosaveEnabled = false
        return BackupManifest(
            folders: try modelContext.fetch(FetchDescriptor<Folder>()).map {
                .init(id: $0.id, title: $0.title, createdAt: $0.createdAt, color: $0.colorRawValue,
                      favorite: $0.isFavorite, trashedAt: $0.trashedAt, parentID: $0.parent?.id)
            },
            notebooks: try modelContext.fetch(FetchDescriptor<Notebook>()).map {
                .init(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt, cover: $0.coverColorRawValue,
                      trashedAt: $0.trashedAt, favorite: $0.isFavorite, folderID: $0.folder?.id)
            },
            sections: try modelContext.fetch(FetchDescriptor<NotebookSection>()).map {
                .init(id: $0.id, title: $0.title, sortIndex: $0.sortIndex, notebookID: $0.notebook?.id)
            },
            pages: try modelContext.fetch(FetchDescriptor<NotePage>()).map {
                .init(id: $0.id, notebookID: $0.notebook?.id, sectionID: $0.section?.id, index: $0.pageIndex,
                      template: $0.paperTemplateRawValue, drawing: $0.drawingFilePath, pdf: $0.pdfFilePath, pdfIndex: $0.pdfPageIndex,
                      width: $0.pageWidth, height: $0.pageHeight, bookmark: $0.bookmarkTitle, objects: $0.objectsData,
                      margin: $0.pdfRightMargin, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            decks: try modelContext.fetch(FetchDescriptor<StudyDeck>()).map {
                .init(id: $0.id, title: $0.title, notebookID: $0.notebookID, createdAt: $0.createdAt, trashedAt: $0.trashedAt)
            },
            cards: try modelContext.fetch(FetchDescriptor<Flashcard>()).map {
                .init(id: $0.id, deckID: $0.deck?.id, question: $0.question, answer: $0.answer,
                      sourceNotebookID: $0.sourceNotebookID, sourcePageID: $0.sourcePageID, createdAt: $0.createdAt,
                      updatedAt: $0.updatedAt, trashedAt: $0.trashedAt, nextReviewAt: $0.nextReviewAt,
                      interval: $0.intervalSeconds, repetitions: $0.repetitionCount, lapses: $0.lapseCount,
                      questionImage: $0.questionImagePath, answerImage: $0.answerImagePath)
            },
            reviews: try modelContext.fetch(FetchDescriptor<ReviewRecord>()).map {
                .init(id: $0.id, cardID: $0.flashcard?.id, reviewedAt: $0.reviewedAt, rating: $0.ratingRawValue,
                      nextReviewAt: $0.nextReviewAt, interval: $0.intervalSeconds, schedulerVersion: $0.schedulerVersion)
            })
    }
}
