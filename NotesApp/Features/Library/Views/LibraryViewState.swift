import SwiftUI
import SwiftData

/// A lazy owner for one library identity. Contained Observation models retain
/// their granular dependencies; rebuilding the view value does not fetch again.
@MainActor final class LibraryViewState: ObservableObject {
    let model: LibraryViewModel
    let navigation: LibraryNavigation
    let workspace: DocumentWorkspace
    let focusMode: EditorFocusMode

    init(context: ModelContext, workspace: DocumentWorkspace?, focusMode: EditorFocusMode?,
         navigation: LibraryNavigation?, workspaceDefaults: UserDefaults) {
        model = LibraryViewModel(context: context)
        self.navigation = navigation ?? LibraryNavigation()
        self.workspace = workspace ?? DocumentWorkspace(context: context, defaults: workspaceDefaults)
        self.focusMode = focusMode ?? EditorFocusMode()
    }
}
