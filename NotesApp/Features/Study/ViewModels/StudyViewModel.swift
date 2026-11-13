import Foundation
import Observation
import SwiftData

struct StudyRoute: Hashable { let deckID: UUID }

struct StudySource: Equatable, Sendable, Identifiable {
    let notebookID: UUID
    let pageID: UUID
    var id: UUID { pageID }
}

enum StudyError: LocalizedError {
    case emptyTitle, emptyCard, unavailableDeck, unavailableCard, unavailableSource, missingNotebook
    case saveFailed(String)
    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a title for this deck."
        case .emptyCard: "Enter both a question and an answer."
        case .unavailableDeck: "This deck is no longer available. Restore it from Study Trash first."
        case .unavailableCard: "This card is no longer available. Your other cards are unchanged."
        case .unavailableSource: "The original page is unavailable. It may have been deleted or moved to Trash. Your card is still available."
        case .missingNotebook: "Choose an available notebook or leave the deck unlinked."
        case .saveFailed(let detail): "The study change could not be saved. Please try again. \(detail)"
        }
    }
}

/// Owns a separate context: rollback here cannot discard unsaved editor metadata.
@MainActor @Observable final class StudyViewModel {
    private(set) var decks: [StudyDeck] = []
    private(set) var cards: [Flashcard] = []
    private(set) var notebooks: [Notebook] = []
    var loadError: String?
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let scheduler: any ReviewScheduling
    @ObservationIgnored private let saveContext: (ModelContext) throws -> Void

    init(container: ModelContainer, scheduler: any ReviewScheduling = SimpleReviewScheduler(),
         save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        context = ModelContext(container); context.autosaveEnabled = false
        self.scheduler = scheduler; self.saveContext = save
        reload()
    }

    func reload() {
        do {
            let decks = try context.fetch(FetchDescriptor<StudyDeck>(sortBy: [SortDescriptor(\.title)]))
            let cards = try context.fetch(FetchDescriptor<Flashcard>(sortBy: [SortDescriptor(\.nextReviewAt), SortDescriptor(\.createdAt)]))
            let books = try context.fetch(FetchDescriptor<Notebook>(sortBy: [SortDescriptor(\.title)]))
            self.decks = decks; self.cards = cards; notebooks = books.filter { !$0.isInTrash }; loadError = nil
        } catch { loadError = "Study could not be loaded. Your saved data has not been removed. \(error.localizedDescription)" }
    }

    var activeDecks: [StudyDeck] { decks.filter { $0.trashedAt == nil } }
    var activeCards: [Flashcard] { cards.filter { !$0.isInTrash && $0.deck != nil } }
    func cards(in deck: StudyDeck) -> [Flashcard] { activeCards.filter { $0.deck?.id == deck.id } }
    func due(at date: Date, deckID: UUID? = nil) -> [Flashcard] {
        activeCards.filter { $0.nextReviewAt <= date && (deckID == nil || $0.deck?.id == deckID) }
            .sorted { $0.nextReviewAt == $1.nextReviewAt ? $0.id.uuidString < $1.id.uuidString : $0.nextReviewAt < $1.nextReviewAt }
    }
    /// Includes overdue cards and cards scheduled later today, using local day boundaries.
    func dueTodayCount(at date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return due(at: date).count }
        return activeCards.filter { $0.nextReviewAt < end }.count
    }
    func notebookTitle(_ id: UUID?) -> String? { id.flatMap { id in notebooks.first { $0.id == id }?.title } }

    @discardableResult func saveDeck(id: UUID? = nil, title: String, notebookID: UUID?) throws -> StudyDeck {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StudyError.emptyTitle }
        let existing = id.flatMap { id in decks.first { $0.id == id } }
        guard id == nil || existing?.trashedAt == nil && existing != nil else { throw StudyError.unavailableDeck }
        if let notebookID, existing?.notebookID != notebookID,
           !notebooks.contains(where: { $0.id == notebookID }) { throw StudyError.missingNotebook }
        let deck = existing ?? StudyDeck(title: title, notebookID: notebookID)
        try commit {
            if existing == nil { context.insert(deck) }
            deck.title = title; deck.notebookID = notebookID
        }
        return deck
    }

    @discardableResult func saveCard(id: UUID? = nil, deckID: UUID, question: String, answer: String,
                                    source: StudySource?, now: Date = .now) throws -> Flashcard {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else { throw StudyError.emptyCard }
        guard let deck = activeDecks.first(where: { $0.id == deckID }) else { throw StudyError.unavailableDeck }
        let existing = id.flatMap { id in cards.first { $0.id == id && !$0.isInTrash } }
        guard id == nil || existing != nil else { throw StudyError.unavailableCard }
        if let source, existing?.sourcePageID != source.pageID || existing?.sourceNotebookID != source.notebookID {
            _ = try resolve(source)
        }
        let card = existing ?? Flashcard(question: question, answer: answer, now: now)
        try commit {
            if existing == nil { context.insert(card) }
            card.deck = deck; card.question = question; card.answer = answer; card.updatedAt = now
            card.sourceNotebookID = source?.notebookID; card.sourcePageID = source?.pageID
        }
        return card
    }

    func trash(_ deck: StudyDeck, now: Date = .now) throws { try commit { deck.trashedAt = now } }
    func trash(_ card: Flashcard, now: Date = .now) throws { try commit { card.trashedAt = now } }
    func restore(_ deck: StudyDeck) throws { try commit { deck.trashedAt = nil } }
    func restore(_ card: Flashcard) throws {
        guard card.deck?.trashedAt == nil, card.deck != nil else { throw StudyError.unavailableDeck }
        try commit { card.trashedAt = nil }
    }

    func schedule(for card: Flashcard, rating: ReviewRating, at date: Date) -> ScheduledReview {
        scheduler.schedule(.init(intervalSeconds: card.intervalSeconds, repetitions: card.repetitionCount,
                                 lapses: card.lapseCount), rating: rating, at: date)
    }

    /// Card state and immutable history are persisted in the same save.
    func review(_ id: UUID, rating: ReviewRating, at date: Date) throws {
        guard let card = activeCards.first(where: { $0.id == id }) else { throw StudyError.unavailableCard }
        let result = schedule(for: card, rating: rating, at: date)
        try commit {
            let record = ReviewRecord(rating: rating.rawValue, reviewedAt: date, nextReviewAt: result.nextReviewAt,
                                      intervalSeconds: result.progress.intervalSeconds)
            context.insert(record); record.flashcard = card
            card.nextReviewAt = result.nextReviewAt; card.intervalSeconds = result.progress.intervalSeconds
            card.repetitionCount = result.progress.repetitions; card.lapseCount = result.progress.lapses
            card.updatedAt = date
        }
    }

    func source(for card: Flashcard) throws -> StudySource {
        guard let notebookID = card.sourceNotebookID, let pageID = card.sourcePageID else { throw StudyError.unavailableSource }
        return try resolve(StudySource(notebookID: notebookID, pageID: pageID))
    }

    private func resolve(_ source: StudySource) throws -> StudySource {
        // Notebook/Trash metadata can change in the library's different context.
        let lookup = ModelContext(context.container)
        lookup.autosaveEnabled = false
        let id = source.pageID
        var request = FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == id }); request.fetchLimit = 1
        guard let page = try lookup.fetch(request).first, let notebook = page.notebook,
              notebook.id == source.notebookID, !notebook.isInTrash else { throw StudyError.unavailableSource }
        return source
    }

    private func commit(_ action: () -> Void) throws {
        action()
        do { try saveContext(context) }
        catch { context.rollback(); throw StudyError.saveFailed(error.localizedDescription) }
        reload()
    }
}
