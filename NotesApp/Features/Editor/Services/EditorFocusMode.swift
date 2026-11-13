import Foundation
import Observation

/// Runtime presentation only. A fresh app launch always has normal navigation.
@MainActor @Observable final class EditorFocusMode {
    private(set) var isActive = false
    private(set) var documentID: UUID?
    func enter(documentID: UUID? = nil) { self.documentID = documentID; isActive = true }
    func exit() { isActive = false; documentID = nil }
}
