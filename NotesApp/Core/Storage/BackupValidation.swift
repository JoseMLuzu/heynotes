import Foundation

enum BackupValidation {
    static func path(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 1024, !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw LibraryBackupError.unsafePath }
    }

    static func requiredFiles(_ manifest: BackupManifest) throws -> Set<String> {
        var paths = Set<String>()
        for page in manifest.pages {
            if let drawing = page.drawing { paths.insert(drawing) }
            if let pdf = page.pdf { paths.insert(pdf) }
            for item in try PageElementsCodec.decode(page.objects) {
                paths.formUnion(item.assetPaths)
            }
        }
        for card in manifest.cards {
            if let path = card.questionImage { paths.insert(path) }
            if let path = card.answerImage { paths.insert(path) }
        }
        for value in paths { try path(value) }
        return paths
    }

    static func manifest(_ value: BackupManifest) throws {
        guard (1...2).contains(value.formatVersion) else { throw LibraryBackupError.unsupportedVersion }
        guard value.formatVersion >= 2 || value.cards.allSatisfy({ $0.questionImage == nil && $0.answerImage == nil }) else { throw LibraryBackupError.invalidMetadata }
        func ids(_ values: [UUID]) throws -> Set<UUID> {
            let set = Set(values)
            guard values.count <= 200_000, set.count == values.count else { throw LibraryBackupError.invalidMetadata }
            return set
        }
        let folders = try ids(value.folders.map(\.id)), books = try ids(value.notebooks.map(\.id))
        let sections = try ids(value.sections.map(\.id)), pages = try ids(value.pages.map(\.id))
        let decks = try ids(value.decks.map(\.id)), cards = try ids(value.cards.map(\.id))
        _ = try ids(value.reviews.map(\.id))
        func exists(_ id: UUID?, in set: Set<UUID>) -> Bool { id.map(set.contains) ?? true }
        guard value.folders.allSatisfy({ exists($0.parentID, in: folders) }),
              value.notebooks.allSatisfy({ exists($0.folderID, in: folders) }),
              value.sections.allSatisfy({ $0.sortIndex >= 0 && exists($0.notebookID, in: books) }),
              value.cards.allSatisfy({ exists($0.deckID, in: decks) && $0.interval.isFinite && $0.interval >= 0 && $0.repetitions >= 0 && $0.lapses >= 0 }),
              value.reviews.allSatisfy({ exists($0.cardID, in: cards) && $0.interval.isFinite && $0.interval >= 0 })
        else { throw LibraryBackupError.invalidMetadata }
        let owners = Dictionary(uniqueKeysWithValues: value.sections.map { ($0.id, $0.notebookID) })
        for page in value.pages {
            guard exists(page.notebookID, in: books), exists(page.sectionID, in: sections), page.index >= 0,
                  page.pdfIndex.map({ $0 >= 0 }) ?? true,
                  page.width.map({ $0.isFinite && $0 > 0 && $0 <= 14400 }) ?? true,
                  page.height.map({ $0.isFinite && $0 > 0 && $0 <= 14400 }) ?? true,
                  page.margin.map({ $0.isFinite && $0 >= 0 && $0 + (page.width ?? 768) <= 14400 }) ?? true
            else { throw LibraryBackupError.invalidMetadata }
            if let section = page.sectionID, owners[section] != .some(page.notebookID) { throw LibraryBackupError.invalidMetadata }
        }
        // A missing original note is legitimate Study state; existing references must agree.
        let pageOwners = Dictionary(uniqueKeysWithValues: value.pages.map { ($0.id, $0.notebookID) })
        for card in value.cards {
            if let page = card.sourcePageID, pages.contains(page), let book = card.sourceNotebookID,
               books.contains(book), pageOwners[page] != .some(book) { throw LibraryBackupError.invalidMetadata }
        }
        let parents = Dictionary(uniqueKeysWithValues: value.folders.map { ($0.id, $0.parentID) })
        var completed = Set<UUID>()
        for folder in value.folders where !completed.contains(folder.id) {
            var branch = Set<UUID>(), current: UUID? = folder.id
            while let id = current, !completed.contains(id) {
                guard branch.insert(id).inserted else { throw LibraryBackupError.invalidMetadata }
                current = parents[id] ?? nil
            }
            completed.formUnion(branch)
        }
        _ = try requiredFiles(value)
    }
}
