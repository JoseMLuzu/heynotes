import Foundation
import CoreGraphics

enum PageSwipe {
    static let creationHoldDuration: TimeInterval = 0.5

    /// Existing pages accept a short, intentional flick or a modest slower swipe.
    static func direction(translation: CGPoint, velocity: CGPoint = .zero, viewportWidth: CGFloat) -> Int? {
        guard abs(translation.x) > abs(translation.y) * 1.4 else { return nil }
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
