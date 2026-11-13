import Foundation
import Observation

enum StudyReviewMode { case scheduled, practice }

/// Scheduled ratings persist before advancing. Free practice never changes stored progress.
@MainActor @Observable final class StudyReviewSession: Identifiable {
    let id = UUID()
    let mode: StudyReviewMode
    private(set) var cardIDs: [UUID]
    private let originalCardIDs: [UUID]
    private(set) var index = 0
    private(set) var isAnswerVisible = false
    private(set) var reviewedCount = 0
    init(cards: [Flashcard], mode: StudyReviewMode = .scheduled) {
        self.mode = mode
        let ordered = mode == .practice ? cards.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        } : cards
        let ids = ordered.map(\.id)
        cardIDs = ids; originalCardIDs = ids
    }
    var isPractice: Bool { mode == .practice }
    var isComplete: Bool { index >= cardIDs.count }
    func current(in model: StudyViewModel) -> Flashcard? {
        guard !isComplete else { return nil }
        return model.activeCards.first { $0.id == cardIDs[index] }
    }
    func reveal() { isAnswerVisible = true }
    func flip() { isAnswerVisible.toggle() }
    func rate(_ rating: ReviewRating, model: StudyViewModel, now: Date = .now) throws {
        guard !isPractice, isAnswerVisible, let card = current(in: model) else { throw StudyError.unavailableCard }
        try model.review(card.id, rating: rating, at: now)
        reviewedCount += 1; advance()
    }
    func advancePractice(model: StudyViewModel) throws {
        guard isPractice, isAnswerVisible, current(in: model) != nil else { throw StudyError.unavailableCard }
        reviewedCount += 1; advance()
    }
    func canRepeat(in model: StudyViewModel) -> Bool {
        guard isPractice else { return false }
        let available = Set(model.activeCards.map(\.id))
        return originalCardIDs.contains { available.contains($0) }
    }
    @discardableResult func repeatPractice(in model: StudyViewModel) -> Bool {
        guard canRepeat(in: model) else { return false }
        let available = Set(model.activeCards.map(\.id))
        cardIDs = originalCardIDs.filter { available.contains($0) }
        index = 0; reviewedCount = 0; isAnswerVisible = false
        return true
    }
    func skip() { advance() }
    private func advance() { if !isComplete { index += 1 }; isAnswerVisible = false }
}
