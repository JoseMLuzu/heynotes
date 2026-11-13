import Foundation
import SwiftData

@Model public final class ReviewRecord {
    @Attribute(.unique) public var id: UUID
    public var flashcard: Flashcard?
    public var reviewedAt: Date
    public var ratingRawValue: String
    public var nextReviewAt: Date
    public var intervalSeconds: Double
    public var schedulerVersion: Int = 1

    public init(rating: String, reviewedAt: Date, nextReviewAt: Date,
                intervalSeconds: Double, id: UUID = UUID()) {
        self.id = id; self.ratingRawValue = rating; self.reviewedAt = reviewedAt
        self.nextReviewAt = nextReviewAt; self.intervalSeconds = intervalSeconds
    }
}
