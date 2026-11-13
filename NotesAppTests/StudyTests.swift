import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct StudyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func practiceIncludesFutureCardsRepeatsAndNeverSavesOrChangesScheduledProgress() throws {
        enum Failure: Error { case unexpectedSave }
        let container = try PersistenceController.makeContainer(inMemory: true)
        var saves = 0, forbidSaves = false
        let model = StudyViewModel(container: container, save: { context in
            if forbidSaves { throw Failure.unexpectedSave }
            saves += 1; try context.save()
        })
        let deck = try model.saveDeck(title: "Practice", notebookID: nil)
        let first = try model.saveCard(deckID: deck.id, question: "First", answer: "A", source: nil, now: now)
        let second = try model.saveCard(deckID: deck.id, question: "Second", answer: "B", source: nil, now: now.addingTimeInterval(1))
        let hidden = try model.saveCard(deckID: deck.id, question: "Trashed", answer: "C", source: nil, now: now)
        let otherDeck = try model.saveDeck(title: "Other", notebookID: nil)
        _ = try model.saveCard(deckID: otherDeck.id, question: "Other", answer: "D", source: nil, now: now)
        try model.review(first.id, rating: .good, at: now); try model.review(second.id, rating: .easy, at: now)
        try model.trash(hidden)
        #expect(model.due(at: now, deckID: deck.id).isEmpty)
        let dates = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0.nextReviewAt) })
        let updated = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0.updatedAt) })
        let progress = Dictionary(uniqueKeysWithValues: model.cards.map {
            ($0.id, ReviewProgress(intervalSeconds: $0.intervalSeconds, repetitions: $0.repetitionCount, lapses: $0.lapseCount))
        })
        let records = Set(model.cards.flatMap(\.reviews).map(\.id)), savedCount = saves
        forbidSaves = true
        let session = StudyReviewSession(cards: model.cards(in: deck), mode: .practice)
        #expect(session.cardIDs == [first.id, second.id])
        #expect(throws: StudyError.self) { try session.advancePractice(model: model) }
        session.reveal()
        #expect(throws: StudyError.self) { try session.rate(.again, model: model, now: now) }
        try session.advancePractice(model: model)
        #expect(session.current(in: model)?.id == second.id && !session.isAnswerVisible)
        session.reveal(); try session.advancePractice(model: model)
        #expect(session.isComplete && session.reviewedCount == 2)
        #expect(session.repeatPractice(in: model))
        #expect(session.index == 0 && session.reviewedCount == 0 && !session.isAnswerVisible)
        #expect(session.current(in: model)?.id == first.id)
        #expect(saves == savedCount && !model.context.hasChanges)
        #expect(Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0.nextReviewAt) }) == dates)
        #expect(Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0.updatedAt) }) == updated)
        #expect(Dictionary(uniqueKeysWithValues: model.cards.map {
            ($0.id, ReviewProgress(intervalSeconds: $0.intervalSeconds, repetitions: $0.repetitionCount, lapses: $0.lapseCount))
        }) == progress)
        #expect(Set(model.cards.flatMap(\.reviews).map(\.id)) == records)
        #expect(model.due(at: now, deckID: deck.id).isEmpty)
        forbidSaves = false
        try model.trash(first)
        #expect(session.repeatPractice(in: model))
        #expect(session.cardIDs == [second.id])
        try model.trash(deck)
        #expect(!session.canRepeat(in: model) && !session.repeatPractice(in: model))
    }

    @Test func sampleDeckIsExplicitAndRepeatedCreationPreservesReviewsAndTrash() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        StudySampleDeck.createIfRequested(in: container)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StudyDeck>()) == 0)
        let result = try StudySampleDeck.create(in: container, now: now)
        #expect(result.cardCount == 8 && !result.trashed)
        let model = StudyViewModel(container: container)
        let card = try #require(model.cards.first)
        #expect(model.due(at: now).count == 8)
        try model.review(card.id, rating: .good, at: now)
        let repeated = try StudySampleDeck.create(in: container, now: now.addingTimeInterval(10))
        #expect(repeated.id == result.id && repeated.cardCount == 8)
        let fresh = StudyViewModel(container: container)
        #expect(fresh.decks.count == 1 && fresh.cards.count == 8)
        #expect(fresh.cards.first { $0.id == card.id }?.reviews.count == 1)
        #expect(fresh.due(at: now).count == 7)
        let deck = try #require(fresh.decks.first)
        try fresh.trash(deck)
        #expect(try StudySampleDeck.create(in: container).trashed)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Notebook>()) == 0)
    }

    @Test func schedulerIntervalsProgressionLapsesAndBounds() {
        let scheduler = SimpleReviewScheduler(), initial = ReviewProgress()
        let expectations: [(ReviewRating, Double)] = [(.again, 600), (.hard, 86_400), (.good, 86_400), (.easy, 345_600)]
        for (rating, interval) in expectations {
            let result = scheduler.schedule(initial, rating: rating, at: now)
            #expect(result.progress.intervalSeconds == interval)
            #expect(result.nextReviewAt.timeIntervalSince(now) == interval)
        }
        let first = scheduler.schedule(initial, rating: .good, at: now)
        let second = scheduler.schedule(first.progress, rating: .good, at: first.nextReviewAt)
        let third = scheduler.schedule(second.progress, rating: .good, at: second.nextReviewAt)
        #expect(second.progress.intervalSeconds == 3 * 86_400)
        #expect(third.progress.intervalSeconds == 7.5 * 86_400)
        let hard = scheduler.schedule(third.progress, rating: .hard, at: now)
        #expect(hard.progress.repetitions == third.progress.repetitions)
        #expect(hard.progress.intervalSeconds == third.progress.intervalSeconds * 1.2)
        let lapse = scheduler.schedule(third.progress, rating: .again, at: now)
        #expect(lapse.progress.repetitions == 0 && lapse.progress.lapses == 1)
        #expect(scheduler.schedule(lapse.progress, rating: .good, at: now).progress.intervalSeconds == 86_400)
        for value in [Double.nan, .infinity, -10, Double.greatestFiniteMagnitude] {
            for rating in ReviewRating.allCases {
                let result = scheduler.schedule(.init(intervalSeconds: value, repetitions: .max, lapses: .max), rating: rating, at: now)
                #expect(result.nextReviewAt > now)
                #expect(result.progress.intervalSeconds <= 365 * 86_400)
                #expect(result.progress.intervalSeconds.isFinite)
            }
        }
    }

    @Test func reviewAndEditsSurviveReopeningDiskStore() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("study.store")
        let cardID: UUID, deckID: UUID
        do {
            let container = try PersistenceController.makeContainer(storeURL: url)
            let model = StudyViewModel(container: container)
            let deck = try model.saveDeck(title: "Biology", notebookID: nil); deckID = deck.id
            let card = try model.saveCard(deckID: deck.id, question: "What is ATP?", answer: "An energy carrier", source: nil, now: now)
            cardID = card.id
            #expect(model.due(at: now).map(\.id) == [cardID])
            let session = StudyReviewSession(cards: model.due(at: now))
            #expect(throws: StudyError.self) { try session.rate(.good, model: model, now: now) }
            session.reveal(); try session.rate(.good, model: model, now: now)
            #expect(session.isComplete && session.reviewedCount == 1)
            #expect(model.due(at: now).isEmpty)
            _ = try model.saveCard(id: card.id, deckID: deck.id, question: "ATP?", answer: "Cellular energy carrier", source: nil, now: now)
            #expect(card.repetitionCount == 1 && card.reviews.count == 1)
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let model = StudyViewModel(container: reopened)
        let card = try #require(model.cards.first)
        #expect(card.id == cardID && card.deck?.id == deckID)
        #expect(card.question == "ATP?" && card.answer == "Cellular energy carrier")
        #expect(card.nextReviewAt == now.addingTimeInterval(86_400))
        #expect(model.due(at: card.nextReviewAt.addingTimeInterval(-1)).isEmpty)
        #expect(model.due(at: card.nextReviewAt).map(\.id) == [cardID])
        let record = try #require(card.reviews.first)
        #expect(record.flashcard?.id == cardID && record.ratingRawValue == "good")
        #expect(record.reviewedAt == now && record.nextReviewAt == card.nextReviewAt && record.schedulerVersion == 1)
    }

    @Test func trashRestoreAndInvalidInputPreserveCardsAndHistory() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = StudyViewModel(container: container)
        #expect(throws: StudyError.self) { try model.saveDeck(title: " \n ", notebookID: nil) }
        let deck = try model.saveDeck(title: "Deck", notebookID: nil)
        #expect(throws: StudyError.self) { try model.saveCard(deckID: deck.id, question: "?", answer: " ", source: nil) }
        let card = try model.saveCard(deckID: deck.id, question: "Question", answer: "Answer", source: nil, now: now)
        try model.review(card.id, rating: .again, at: now)
        try model.trash(card); try model.trash(deck)
        #expect(model.activeCards.isEmpty && model.activeDecks.isEmpty)
        #expect(throws: StudyError.self) { try model.restore(card) }
        try model.restore(deck)
        #expect(model.activeCards.isEmpty)
        try model.restore(card)
        #expect(model.activeCards.map(\.id) == [card.id])
        #expect(card.reviews.count == 1 && card.lapseCount == 1)
        try model.trash(deck); try model.restore(deck)
        #expect(model.activeCards.count == 1 && model.cards.count == 1)
    }

    @Test func failedReviewDoesNotAdvanceOrLoseHistoryAndCannotRollbackEditor() throws {
        enum Failure: Error { case diskFull }
        let container = try PersistenceController.makeContainer(inMemory: true)
        var fail = false
        let model = StudyViewModel(container: container, save: { context in
            if fail { throw Failure.diskFull }; try context.save()
        })
        let notebook = Notebook(title: "Saved")
        container.mainContext.insert(notebook); try container.mainContext.save()
        notebook.title = "Unsaved editor metadata"
        let deck = try model.saveDeck(title: "Deck", notebookID: nil)
        let card = try model.saveCard(deckID: deck.id, question: "Q", answer: "A", source: nil, now: now)
        let session = StudyReviewSession(cards: [card]); session.reveal(); fail = true
        #expect(throws: StudyError.self) { try session.rate(.good, model: model, now: now) }
        #expect(session.index == 0 && session.isAnswerVisible && session.reviewedCount == 0)
        #expect(card.nextReviewAt == now && card.repetitionCount == 0 && card.reviews.isEmpty)
        #expect(try model.context.fetchCount(FetchDescriptor<ReviewRecord>()) == 0)
        #expect(notebook.title == "Unsaved editor metadata" && container.mainContext.hasChanges)
        fail = false; try session.rate(.good, model: model, now: now)
        #expect(session.isComplete && card.reviews.count == 1)
    }

    @Test func permanentSourceLinksSurviveOrderingAndMissingPagesStayEditable() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let book = Notebook(title: "Notes"), page = NotePage(pageIndex: 0), other = NotePage(pageIndex: 1)
        container.mainContext.insert(book); container.mainContext.insert(page); container.mainContext.insert(other)
        book.pages = [page, other]; try container.mainContext.save()
        let model = StudyViewModel(container: container)
        let deck = try model.saveDeck(title: "Linked", notebookID: book.id)
        let source = StudySource(notebookID: book.id, pageID: page.id)
        let card = try model.saveCard(deckID: deck.id, question: "Q", answer: "A", source: source)
        page.pageIndex = 1; other.pageIndex = 0; try container.mainContext.save()
        #expect(try model.source(for: card) == source)
        book.trashedAt = now; try container.mainContext.save()
        #expect(throws: StudyError.self) { try model.source(for: card) }
        book.trashedAt = nil; try container.mainContext.save()
        #expect(try model.source(for: card) == source)
        #expect(throws: StudyError.self) {
            try model.saveCard(deckID: deck.id, question: "Bad", answer: "Source", source: .init(notebookID: UUID(), pageID: page.id))
        }
        // Deleting the actual source cannot cascade into cards or review records.
        container.mainContext.delete(page); try container.mainContext.save()
        #expect(throws: StudyError.self) { try model.source(for: card) }
        _ = try model.saveCard(id: card.id, deckID: deck.id, question: "Updated", answer: "Kept", source: source)
        #expect(card.sourcePageID == source.pageID && card.question == "Updated")
        _ = try model.saveCard(id: card.id, deckID: deck.id, question: "Updated", answer: "Kept", source: nil)
        #expect(card.sourcePageID == nil && card.sourceNotebookID == nil)
    }

    @Test func failedCreatesAndEditsRollbackAndSkippedCardsRemainDue() throws {
        enum Failure: Error { case diskFull }
        let container = try PersistenceController.makeContainer(inMemory: true)
        var fail = true
        let model = StudyViewModel(container: container, save: { context in
            if fail { throw Failure.diskFull }; try context.save()
        })
        #expect(throws: StudyError.self) { try model.saveDeck(title: "Not saved", notebookID: nil) }
        #expect(try model.context.fetchCount(FetchDescriptor<StudyDeck>()) == 0)
        fail = false
        let deck = try model.saveDeck(title: "Original", notebookID: nil)
        let card = try model.saveCard(deckID: deck.id, question: "Original Q", answer: "Original A", source: nil, now: now)
        fail = true
        #expect(throws: StudyError.self) { try model.saveDeck(id: deck.id, title: "Changed", notebookID: nil) }
        #expect(deck.title == "Original")
        #expect(throws: StudyError.self) {
            try model.saveCard(id: card.id, deckID: deck.id, question: "Changed Q", answer: "Changed A", source: nil)
        }
        #expect(card.question == "Original Q" && card.answer == "Original A")
        let session = StudyReviewSession(cards: [card]); session.skip()
        #expect(session.isComplete && session.reviewedCount == 0)
        #expect(model.due(at: now).map(\.id) == [card.id])
        #expect(card.reviews.isEmpty)
    }

    @Test func dueTodayUsesLocalDayAndIncludesOverdueAcrossDST() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = StudyViewModel(container: container)
        let deck = try model.saveDeck(title: "Day boundary", notebookID: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(end.timeIntervalSince(start) == 23 * 3600)
        for (index, date) in [start.addingTimeInterval(-86_400), start, end.addingTimeInterval(-1), end].enumerated() {
            _ = try model.saveCard(deckID: deck.id, question: "Q\(index)", answer: "A", source: nil, now: date)
        }
        #expect(model.dueTodayCount(at: start, calendar: calendar) == 3)
        #expect(model.due(at: start).count == 2)
        try model.trash(deck)
        #expect(model.dueTodayCount(at: start, calendar: calendar) == 0)
    }

    @Test func shippedV5TopLevelModelLayoutMigratesToFrozenPlan() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("shipped-v5.store"), id = UUID(), pageID = UUID()
        do {
            // Before freezing V5, its schema referenced these same four top-level classes.
            // Their persisted fields remain unchanged in V6.
            let schema = Schema([Folder.self, Notebook.self, NotePage.self, NotebookSection.self], version: .init(5, 0, 0))
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let folder = Folder(title: "Kept"); folder.color = .blue
            let book = Notebook(title: "Existing V5", folder: folder, id: id)
            let page = NotePage(pageIndex: 0, id: pageID); page.drawingFilePath = "Notebooks/kept.drawing"
            old.mainContext.insert(folder); old.mainContext.insert(book); old.mainContext.insert(page)
            book.pages = [page]; try old.mainContext.save()
        }
        let current = try PersistenceController.makeContainer(storeURL: url)
        let book = try #require(current.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        #expect(book.id == id && book.pages.first?.id == pageID)
        #expect(book.folder?.color == .blue && book.pages.first?.drawingFilePath == "Notebooks/kept.drawing")
        #expect(try current.mainContext.fetchCount(FetchDescriptor<StudyDeck>()) == 0)
    }
}
