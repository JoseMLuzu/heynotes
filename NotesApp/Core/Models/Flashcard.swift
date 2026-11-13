import Foundation
import SwiftData

@Model public final class Flashcard {
    @Attribute(.unique) public var id: UUID
    public var deck: StudyDeck?
    public var question: String
    public var answer: String
    public var sourceNotebookID: UUID?
    public var sourcePageID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?
    public var nextReviewAt: Date
    public var intervalSeconds: Double = 0
    public var repetitionCount: Int = 0
    public var lapseCount: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \ReviewRecord.flashcard)
    public var reviews: [ReviewRecord] = []

    public var isInTrash: Bool { trashedAt != nil || deck?.trashedAt != nil }

    public init(question: String, answer: String, sourceNotebookID: UUID? = nil,
                sourcePageID: UUID? = nil, id: UUID = UUID(), now: Date = .now) {
        self.id = id; self.question = question; self.answer = answer
        self.sourceNotebookID = sourceNotebookID; self.sourcePageID = sourcePageID
        self.createdAt = now; self.updatedAt = now; self.nextReviewAt = now
    }
}
