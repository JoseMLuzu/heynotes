import Foundation
import Observation

enum LibrarySection: Hashable {
    case library, inbox, favorites, study, trash, folder(UUID)
}

@MainActor @Observable final class LibraryNavigation {
    var selection: LibrarySection? = .library
    var studyPath: [StudyRoute] = []

    func folder(in folders: [Folder]) -> Folder? {
        guard case .folder(let id) = selection else { return nil }
        return folders.first { $0.id == id }
    }

    func open(_ folder: Folder) {
        selection = .folder(folder.id)
    }

    func backDestination(in folders: [Folder]) -> String? {
        switch selection {
        case .library, nil: nil
        case .folder: folder(in: folders)?.parent?.title ?? "Library"
        default: "Library"
        }
    }

    func goBack(in folders: [Folder]) {
        guard backDestination(in: folders) != nil else { return }
        if let parent = folder(in: folders)?.parent, !parent.isInTrash {
            selection = .folder(parent.id)
        } else {
            selection = .library
        }
    }
}
