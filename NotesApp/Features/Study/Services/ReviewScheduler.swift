import Foundation

public enum ReviewRating: String, CaseIterable, Identifiable, Sendable {
    case again, hard, good, easy
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ReviewProgress: Equatable, Sendable {
    public var intervalSeconds: Double
    public var repetitions: Int
    public var lapses: Int
    public init(intervalSeconds: Double = 0, repetitions: Int = 0, lapses: Int = 0) {
        self.intervalSeconds = intervalSeconds; self.repetitions = repetitions; self.lapses = lapses
    }
}

public struct ScheduledReview: Equatable, Sendable {
    public let progress: ReviewProgress
    public let nextReviewAt: Date
}

public protocol ReviewScheduling: Sendable {
    func schedule(_ progress: ReviewProgress, rating: ReviewRating, at date: Date) -> ScheduledReview
}

/// V1: fixed elapsed-time intervals, capped at one year. No calendar/DST dependence.
/// Again resets successful repetitions; Hard preserves them; Good/Easy advance them.
public struct SimpleReviewScheduler: ReviewScheduling {
    public init() {}
    public func schedule(_ progress: ReviewProgress, rating: ReviewRating, at date: Date) -> ScheduledReview {
        let day = 86_400.0, cap = 365.0 * 86_400
        let previous = progress.intervalSeconds.isFinite ? max(0, min(cap, progress.intervalSeconds)) : 0
        let repetitions = min(100_000, max(0, progress.repetitions))
        let lapses = min(100_000, max(0, progress.lapses))
        let interval: Double
        let nextRepetitions: Int
        switch rating {
        case .again: interval = 600; nextRepetitions = 0
        case .hard: interval = max(day, previous * 1.2); nextRepetitions = repetitions
        case .good:
            interval = repetitions == 0 ? day : (repetitions == 1 ? 3 * day : max(day, previous * 2.5))
            nextRepetitions = repetitions + 1
        case .easy: interval = max(4 * day, previous * 3.5); nextRepetitions = repetitions + 1
        }
        let seconds = min(cap, interval)
        return ScheduledReview(progress: .init(intervalSeconds: seconds, repetitions: nextRepetitions,
                                               lapses: lapses + (rating == .again ? 1 : 0)),
                               nextReviewAt: date.addingTimeInterval(seconds))
    }
}
