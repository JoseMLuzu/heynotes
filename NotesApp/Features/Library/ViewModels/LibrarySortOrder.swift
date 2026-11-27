import Foundation

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case name, recent, type

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .recent: "Recent"
        case .type: "Type"
        }
    }

    @MainActor func sortedNotebooks(_ notebooks: [Notebook]) -> [Notebook] {
        // Read SwiftData once per item; comparison only touches copied values.
        notebooks.map { notebook in
            (notebook: notebook, key: SortKey(title: notebook.title, id: notebook.id.uuidString,
                date: self == .recent ? notebook.updatedAt : .distantPast,
                isPDF: self == .type && notebook.pages.contains { $0.trashedAt == nil && $0.pdfFilePath != nil }))
        }.sorted { left, right in
            if self == .recent, left.key.date != right.key.date { return left.key.date > right.key.date }
            if self == .type, left.key.isPDF != right.key.isPDF { return !left.key.isPDF }
            return comesBefore(left.key, right.key)
        }.map(\.notebook)
    }

    @MainActor func sortedFolders(_ visible: [Folder], allFolders: [Folder], notebooks: [Notebook]) -> [Folder] {
        var activity: [UUID: Date] = [:]
        if self == .recent {
            // Snapshot each parent link once, including ancestors outside the supplied list.
            // A fresh snapshot reflects moves/edits immediately without cache invalidation.
            struct ParentLink { let parentID: UUID? }
            var parents: [UUID: ParentLink] = [:]
            func capture(_ folder: Folder?) {
                var current = folder
                while let folder = current {
                    let id = folder.id
                    guard parents[id] == nil else { break }
                    let parent = folder.parent
                    parents[id] = ParentLink(parentID: parent?.id)
                    current = parent
                }
            }
            func record(_ date: Date, in id: UUID?) {
                var current = id
                var visited = Set<UUID>()
                while let id = current, visited.insert(id).inserted {
                    activity[id] = max(activity[id] ?? .distantPast, date)
                    current = parents[id]?.parentID
                }
            }
            for folder in allFolders {
                capture(folder); record(folder.createdAt, in: folder.id)
            }
            for notebook in notebooks {
                let folder = notebook.folder
                capture(folder); record(notebook.updatedAt, in: folder?.id)
            }
        }
        return visible.map { folder in
            (folder: folder, key: SortKey(title: folder.title, id: folder.id.uuidString,
                date: self == .recent ? activity[folder.id] ?? folder.createdAt : .distantPast))
        }.sorted { left, right in
            if self == .recent, left.key.date != right.key.date { return left.key.date > right.key.date }
            return comesBefore(left.key, right.key)
        }.map(\.folder)
    }

    private struct SortKey {
        let title: String
        let id: String
        var date: Date = .distantPast
        var isPDF = false
    }

    private func comesBefore(_ left: SortKey, _ right: SortKey) -> Bool {
        let comparison = left.title.localizedStandardCompare(right.title)
        return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
    }
}
