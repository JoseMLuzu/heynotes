import Foundation

public extension Folder {
    var isInTrash: Bool {
        var current: Folder? = self
        var visited = Set<UUID>()
        while let folder = current {
            guard visited.insert(folder.id).inserted else { return true }
            if folder.trashedAt != nil { return true }
            current = folder.parent
        }
        return false
    }

    var visibleChildren: [Folder]? {
        let result = children.filter { !$0.isInTrash }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return result.isEmpty ? nil : result
    }

    var pathTitle: String {
        var names: [String] = [], visited = Set<UUID>()
        var current: Folder? = self
        while let folder = current, visited.insert(folder.id).inserted {
            names.append(folder.title); current = folder.parent
        }
        return names.reversed().joined(separator: " / ")
    }

    var subtreeIDs: Set<UUID> {
        var result = Set<UUID>(), pending = [self]
        while let next = pending.popLast() {
            if result.insert(next.id).inserted { pending.append(contentsOf: next.children) }
        }
        return result
    }
}

public extension Notebook {
    var isInTrash: Bool { trashedAt != nil || folder?.isInTrash == true }
}
