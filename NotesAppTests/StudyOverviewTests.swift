import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct StudyOverviewTests {
    @Test func overviewMatchesExistingQueriesAcrossTrashOrphansAndDayBoundaries() throws {
        let container = try PersistenceController.makeContainer(inMemory: true), context = container.mainContext
        let book = Notebook(title: "Biology"), deck = StudyDeck(title: "Active", notebookID: book.id)
        let trashed = StudyDeck(title: "Archived"), empty = StudyDeck(title: "Empty")
        trashed.trashedAt = .now
        context.insert(book); context.insert(deck); context.insert(trashed); context.insert(empty)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let dates = [now.addingTimeInterval(-86_400), now, now.addingTimeInterval(60), tomorrow, tomorrow.addingTimeInterval(3600)]
        for (index, date) in dates.enumerated() {
            let card = Flashcard(question: "Q \(index)", answer: "A", now: now.addingTimeInterval(Double(index)))
            card.nextReviewAt = date; context.insert(card); deck.cards.append(card)
        }
        let hidden = Flashcard(question: "Hidden", answer: "A", now: now); hidden.trashedAt = now
        let archived = Flashcard(question: "Archived", answer: "A", now: now)
        let orphan = Flashcard(question: "Unowned", answer: "A", now: now)
        context.insert(hidden); context.insert(archived); context.insert(orphan)
        deck.cards.append(hidden); trashed.cards.append(archived)
        try context.save()
        let model = StudyViewModel(container: container)
        let overview = model.overview(at: now, calendar: calendar)
        #expect(overview.totalCards == model.activeCards.count)
        #expect(overview.dueToday == model.dueTodayCount(at: now, calendar: calendar))
        #expect(overview.dueCards.map(\.id) == model.due(at: now).map(\.id))
        #expect(overview.nextReviewAt == model.activeCards.map(\.nextReviewAt).min())
        #expect(overview.notebookTitles[book.id] == model.notebookTitle(book.id))
        for value in model.activeDecks {
            #expect(overview.counts(for: value.id).cards == model.cards(in: value).count)
            #expect(overview.counts(for: value.id).due == model.due(at: now, deckID: value.id).count)
        }
        #expect(overview.counts(for: empty.id).cards == 0)
        #expect(overview.counts(for: UUID()).due == 0)
    }

    @Test func freshOverviewReflectsReviewsEditsAndTrashWithoutACacheOrWrites() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        var writes = 0
        let model = StudyViewModel(container: container, save: { writes += 1; try $0.save() })
        let now = Date.now
        let deck = try model.saveDeck(title: "Course", notebookID: nil)
        let card = try model.saveCard(deckID: deck.id, question: "Q", answer: "A", source: nil, now: now)
        let before = writes
        for _ in 0..<3 { #expect(model.overview(at: now).dueCards.count == 1) }
        #expect(writes == before)
        try model.review(card.id, rating: .easy, at: now)
        #expect(model.overview(at: now).dueCards.isEmpty)
        #expect(model.overview(at: now).totalCards == 1)
        try model.trash(card)
        #expect(model.overview(at: now).totalCards == 0)
        #expect(model.overview(at: now).nextReviewAt == nil)
    }
}
