import Foundation
import SwiftData

struct BackupRestoreResult: Sendable {
    let notebooks: Int
    let pages: Int
    let decks: Int
    let cards: Int
}

extension BackupMetadataStore {
    /// One metadata transaction. Existing records are never updated or deleted.
    func restore(_ snapshot: BackupManifest, paths: [String: String],
                 save: @Sendable (ModelContext) throws -> Void) throws -> BackupRestoreResult {
        try BackupValidation.manifest(snapshot)
        modelContext.autosaveEnabled = false
        var committed = false
        defer { if !committed { modelContext.rollback() } }
        func mapping(_ ids: [UUID], occupied: Set<UUID>) -> [UUID: UUID] {
            var reserved = occupied.union(ids), result: [UUID: UUID] = [:]
            for original in ids {
                var id = original
                if occupied.contains(id) {
                    repeat { id = UUID() } while reserved.contains(id)
                }
                reserved.insert(id); result[original] = id
            }
            return result
        }
        let folderIDs = mapping(snapshot.folders.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<Folder>()).map(\.id)))
        let bookIDs = mapping(snapshot.notebooks.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<Notebook>()).map(\.id)))
        let sectionIDs = mapping(snapshot.sections.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<NotebookSection>()).map(\.id)))
        let pageIDs = mapping(snapshot.pages.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<NotePage>()).map(\.id)))
        let deckIDs = mapping(snapshot.decks.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<StudyDeck>()).map(\.id)))
        let cardIDs = mapping(snapshot.cards.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<Flashcard>()).map(\.id)))
        let reviewIDs = mapping(snapshot.reviews.map(\.id), occupied: Set(try modelContext.fetch(FetchDescriptor<ReviewRecord>()).map(\.id)))
        func reference(_ id: UUID?, in map: [UUID: UUID]) -> UUID? { id.map { map[$0] ?? $0 } }
        func path(_ original: String?) throws -> String? {
            guard let original else { return nil }
            guard let mapped = paths[original] else { throw LibraryBackupError.missingFile(original) }
            return mapped
        }
        var folders: [UUID: Folder] = [:], books: [UUID: Notebook] = [:]
        var sections: [UUID: NotebookSection] = [:], decks: [UUID: StudyDeck] = [:], cards: [UUID: Flashcard] = [:]
        for record in snapshot.folders {
            let item = Folder(title: record.title, id: folderIDs[record.id]!, createdAt: record.createdAt)
            item.colorRawValue = record.color; item.isFavorite = record.favorite; item.trashedAt = record.trashedAt
            modelContext.insert(item); folders[record.id] = item
        }
        for record in snapshot.folders { folders[record.id]?.parent = record.parentID.flatMap { folders[$0] } }
        for record in snapshot.notebooks {
            let item = Notebook(title: record.title, folder: record.folderID.flatMap { folders[$0] },
                                id: bookIDs[record.id]!, now: record.createdAt)
            item.coverColorRawValue = record.cover; item.updatedAt = record.updatedAt
            item.trashedAt = record.trashedAt; item.isFavorite = record.favorite
            modelContext.insert(item); books[record.id] = item
        }
        for record in snapshot.sections {
            let item = NotebookSection(title: record.title, sortIndex: record.sortIndex, id: sectionIDs[record.id]!)
            modelContext.insert(item); item.notebook = record.notebookID.flatMap { books[$0] }; sections[record.id] = item
        }
        for record in snapshot.pages {
            try Task.checkCancellation()
            let item = NotePage(pageIndex: record.index, id: pageIDs[record.id]!, now: record.createdAt)
            item.paperTemplateRawValue = record.template; item.updatedAt = record.updatedAt
            item.drawingFilePath = try path(record.drawing)
            if item.drawingFilePath == nil, let book = record.notebookID {
                // Recover a deterministic drawing written before its metadata checkpoint.
                item.drawingFilePath = paths[DrawingStorage.path(notebook: book, page: record.id)]
            }
            item.pdfFilePath = try path(record.pdf); item.pdfPageIndex = record.pdfIndex
            item.pageWidth = record.width; item.pageHeight = record.height; item.bookmarkTitle = record.bookmark
            item.pdfRightMargin = record.margin
            if record.objects != nil {
                var objects = try PageElementsCodec.decode(record.objects)
                if objects.contains(where: { $0.imagePath != nil || $0.fontFilePath != nil }) {
                    for index in objects.indices {
                        objects[index].imagePath = try path(objects[index].imagePath)
                        objects[index].fontFilePath = try path(objects[index].fontFilePath)
                    }
                    item.objectsData = try PageElementsCodec.encode(objects)
                } else { item.objectsData = record.objects }
            }
            modelContext.insert(item)
            item.notebook = record.notebookID.flatMap { books[$0] }; item.section = record.sectionID.flatMap { sections[$0] }
        }
        for record in snapshot.decks {
            let item = StudyDeck(title: record.title, notebookID: reference(record.notebookID, in: bookIDs),
                                 id: deckIDs[record.id]!, now: record.createdAt)
            item.trashedAt = record.trashedAt; modelContext.insert(item); decks[record.id] = item
        }
        for record in snapshot.cards {
            let item = Flashcard(question: record.question, answer: record.answer,
                                 sourceNotebookID: reference(record.sourceNotebookID, in: bookIDs),
                                 sourcePageID: reference(record.sourcePageID, in: pageIDs), id: cardIDs[record.id]!, now: record.createdAt)
            item.updatedAt = record.updatedAt; item.trashedAt = record.trashedAt; item.nextReviewAt = record.nextReviewAt
            item.intervalSeconds = record.interval; item.repetitionCount = record.repetitions; item.lapseCount = record.lapses
            item.questionImagePath = try path(record.questionImage); item.answerImagePath = try path(record.answerImage)
            modelContext.insert(item); item.deck = record.deckID.flatMap { decks[$0] }; cards[record.id] = item
        }
        for record in snapshot.reviews {
            let item = ReviewRecord(rating: record.rating, reviewedAt: record.reviewedAt, nextReviewAt: record.nextReviewAt,
                                    intervalSeconds: record.interval, id: reviewIDs[record.id]!)
            item.schedulerVersion = record.schedulerVersion
            modelContext.insert(item); item.flashcard = record.cardID.flatMap { cards[$0] }
        }
        try Task.checkCancellation()
        try save(modelContext)
        committed = true
        return .init(notebooks: snapshot.notebooks.count, pages: snapshot.pages.count, decks: snapshot.decks.count, cards: snapshot.cards.count)
    }
}
