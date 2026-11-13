import Foundation
import CoreGraphics

enum PageTurnMotion {
    static func followUpDuration(duration: TimeInterval, progress: CGFloat) -> TimeInterval {
        min(0.06, max(0, duration * Double(1 - min(1, max(0, progress)))))
    }

    static func distance(viewportWidth: CGFloat, renderedPageWidth: CGFloat = 0) -> CGFloat {
        max(1, max(viewportWidth, renderedPageWidth)) + 16
    }

    static func duration(distance: CGFloat, velocity: CGFloat) -> TimeInterval {
        let speed = velocity.isFinite ? abs(velocity) : 0
        guard speed > 350 else { return 0.24 }
        return min(0.24, max(0.16, Double(abs(distance) / speed) * 0.65))
    }

    static func pull(_ translation: CGFloat, hasDestination: Bool, viewportWidth: CGFloat) -> CGFloat {
        guard translation.isFinite else { return 0 }
        let limit = max(1, viewportWidth) * 0.85
        if hasDestination { return min(limit, max(-limit, translation)) }
        return min(24, max(-24, translation * 0.18))
    }
}

enum PageSwipe {
    static let creationHoldDuration: TimeInterval = 0.5

    /// Existing pages accept a short, intentional flick or a modest slower swipe.
    static func direction(translation: CGPoint, velocity: CGPoint = .zero, viewportWidth: CGFloat) -> Int? {
        guard abs(translation.x) > abs(translation.y) * 1.4 else { return nil }
        // A decisive reverse flick cancels even after a long pull towards the other page.
        if abs(velocity.x) >= 350, translation.x * velocity.x < 0 { return nil }
        let distance = max(36, min(52, viewportWidth * 0.055))
        let flick = abs(translation.x) >= 12 && abs(velocity.x) >= 350 &&
            abs(velocity.x) > abs(velocity.y) * 1.2 && translation.x * velocity.x > 0
        guard abs(translation.x) >= distance || flick else { return nil }
        return translation.x < 0 ? 1 : -1
    }

    static func isCreationPull(_ translation: CGPoint, viewportWidth: CGFloat) -> Bool {
        let distance = max(56, min(80, viewportWidth * 0.09))
        return translation.x <= -distance && abs(translation.x) > abs(translation.y) * 1.4
    }
}

/// Monotonic time is supplied by the view; tests need neither sleeps nor UIKit touches.
struct PageCreationHold {
    enum Update: Equatable { case inactive, progress(Double), commit }
    private var startedAt: TimeInterval?
    private(set) var didCommit = false
    var isWaiting: Bool { startedAt != nil && !didCommit }

    mutating func update(eligible: Bool, now: TimeInterval) -> Update {
        guard !didCommit else { return .inactive }
        guard eligible else { startedAt = nil; return .inactive }
        guard let startedAt else { self.startedAt = now; return .progress(0) }
        let elapsed = max(0, now - startedAt)
        if elapsed >= PageSwipe.creationHoldDuration {
            didCommit = true; self.startedAt = nil; return .commit
        }
        return .progress(elapsed / PageSwipe.creationHoldDuration)
    }
    mutating func cancel() { startedAt = nil }
    mutating func reset() { startedAt = nil; didCommit = false }
}
