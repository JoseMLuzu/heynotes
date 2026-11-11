import Observation

/// Runtime presentation only. A fresh app launch always has normal navigation.
@MainActor @Observable final class EditorFocusMode {
    private(set) var isActive = false
    func enter() { isActive = true }
    func exit() { isActive = false }
}
