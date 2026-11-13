import Foundation
import SwiftData

@Model public final class StudyDeck {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notebookID: UUID?
    public var createdAt: Date
    public var trashedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck)
    public var cards: [Flashcard] = []

    public init(title: String, notebookID: UUID? = nil, id: UUID = UUID(), now: Date = .now) {
        self.id = id; self.title = title; self.notebookID = notebookID; self.createdAt = now
    }
}
