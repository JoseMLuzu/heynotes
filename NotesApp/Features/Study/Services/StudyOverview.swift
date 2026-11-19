import Foundation

struct StudyDeckCounts {
    var cards = 0
    var due = 0
}

/// One render-time snapshot; no stored cache to invalidate after edits, reviews or Trash.
@MainActor struct StudyOverview {
    let totalCards: Int
    let dueToday: Int
    let dueCards: [Flashcard]
    let nextReviewAt: Date?
    let countsByDeck: [UUID: StudyDeckCounts]
    let notebookTitles: [UUID: String]

    func counts(for deckID: UUID) -> StudyDeckCounts { countsByDeck[deckID] ?? StudyDeckCounts() }
}

extension StudyViewModel {
    func overview(at date: Date, calendar: Calendar = .current) -> StudyOverview {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        var counts: [UUID: StudyDeckCounts] = [:]
        var due: [(card: Flashcard, reviewAt: Date, createdAt: Date)] = []
        var total = 0, today = 0
        var next: Date?
        for card in cards {
            guard !card.isInTrash, let deckID = card.deck?.id else { continue }
            let reviewAt = card.nextReviewAt
            total += 1
            var deck = counts[deckID] ?? StudyDeckCounts(); deck.cards += 1
            if reviewAt <= date { due.append((card, reviewAt, card.createdAt)); deck.due += 1 }
            if let dayEnd, reviewAt < dayEnd { today += 1 }
            if next.map({ reviewAt < $0 }) ?? true { next = reviewAt }
            counts[deckID] = deck
        }
        due.sort { $0.reviewAt == $1.reviewAt ? $0.createdAt < $1.createdAt : $0.reviewAt < $1.reviewAt }
        return StudyOverview(totalCards: total, dueToday: today, dueCards: due.map { $0.card }, nextReviewAt: next,
            countsByDeck: counts, notebookTitles: Dictionary(uniqueKeysWithValues: notebooks.map { ($0.id, $0.title) }))
    }
}
