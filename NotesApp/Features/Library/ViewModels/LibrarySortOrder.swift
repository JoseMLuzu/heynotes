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
        let pdfIDs: Set<UUID> = self == .type
            ? Set(notebooks.filter { $0.pages.contains { $0.pdfFilePath != nil } }.map(\.id))
            : []
        return notebooks.sorted { left, right in
            if self == .recent, left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            if self == .type, pdfIDs.contains(left.id) != pdfIDs.contains(right.id) {
                return !pdfIDs.contains(left.id)
            }
            return comesBefore(left.title, id: left.id, right.title, id: right.id)
        }
    }

    @MainActor func sortedFolders(_ visible: [Folder], allFolders: [Folder], notebooks: [Notebook]) -> [Folder] {
        var activity: [UUID: Date] = [:]
        if self == .recent {
            // Propagate real creation/edit dates so a nested edit also updates its visible ancestors.
            func record(_ date: Date, in folder: Folder?) {
                var current = folder
                var visited = Set<UUID>()
                while let folder = current, visited.insert(folder.id).inserted {
                    activity[folder.id] = max(activity[folder.id] ?? .distantPast, date)
                    current = folder.parent
                }
            }
            for folder in allFolders { record(folder.createdAt, in: folder) }
            for notebook in notebooks { record(notebook.updatedAt, in: notebook.folder) }
        }
        return visible.sorted { left, right in
            if self == .recent {
                let leftDate = activity[left.id] ?? left.createdAt
                let rightDate = activity[right.id] ?? right.createdAt
                if leftDate != rightDate { return leftDate > rightDate }
            }
            return comesBefore(left.title, id: left.id, right.title, id: right.id)
        }
    }

    private func comesBefore(_ left: String, id leftID: UUID, _ right: String, id rightID: UUID) -> Bool {
        let comparison = left.localizedStandardCompare(right)
        return comparison == .orderedSame ? leftID.uuidString < rightID.uuidString : comparison == .orderedAscending
    }
}
