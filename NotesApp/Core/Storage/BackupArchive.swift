import Foundation
import CryptoKit

enum BackupArchive {
    static func write(_ manifest: BackupManifest, root: URL) throws -> URL {
        try BackupValidation.manifest(manifest)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let metadata = try encoder.encode(manifest)
        guard metadata.count <= BackupArchiveIO.maximumManifest else { throw LibraryBackupError.tooLarge }
        let files = try enumerate(root)
        let paths = Set(files.map(\.path))
        for path in try BackupValidation.requiredFiles(manifest) where !paths.contains(path) {
            throw LibraryBackupError.missingFile(path)
        }
        let temporary = try BackupArchiveIO.temporaryDirectory()
        var succeeded = false
        defer { if !succeeded { BackupArchiveIO.discardTemporary(temporary) } }
        let partial = temporary.appendingPathComponent("archive.partial")
        let output = try BackupArchiveIO.create(partial)
        defer { try? output.close() }
        try output.write(contentsOf: BackupArchiveIO.magic)
        try output.write(contentsOf: BackupArchiveIO.integer(UInt64(metadata.count)))
        try output.write(contentsOf: Data(SHA256.hash(data: metadata)))
        try output.write(contentsOf: metadata)
        try output.write(contentsOf: BackupArchiveIO.integer(UInt64(files.count)))
        for file in files {
            try Task.checkCancellation()
            let path = Data(file.path.utf8)
            try output.write(contentsOf: BackupArchiveIO.integer(UInt64(path.count)))
            try output.write(contentsOf: path)
            try output.write(contentsOf: BackupArchiveIO.integer(file.size))
            let digestOffset = try output.offset()
            try output.write(contentsOf: Data(repeating: 0, count: 32))
            let input = try FileHandle(forReadingFrom: root.appendingPathComponent(file.path))
            defer { try? input.close() }
            let digest = try BackupArchiveIO.copy(input, to: output, size: file.size)
            if let extra = try input.read(upToCount: 1), !extra.isEmpty { throw LibraryBackupError.changedFile }
            let end = try output.offset()
            try output.seek(toOffset: digestOffset); try output.write(contentsOf: digest); try output.seek(toOffset: end)
        }
        try output.synchronize(); try output.close()
        try Task.checkCancellation()
        let date = manifest.createdAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let result = temporary.appendingPathComponent("HeyNotes-\(date).heynotesbackup")
        try FileManager.default.moveItem(at: partial, to: result)
        succeeded = true; return result
    }

    static func prepare(_ source: URL) throws -> PreparedLibraryBackup {
        let temporary = try BackupArchiveIO.temporaryDirectory()
        var succeeded = false
        defer { if !succeeded { BackupArchiveIO.discardTemporary(temporary) } }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var result: PreparedLibraryBackup?, failure: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            do { result = try extract(url, to: temporary) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
        guard let result else { throw LibraryBackupError.invalidArchive }
        succeeded = true; return result
    }

    private static func extract(_ source: URL, to temporary: URL) throws -> PreparedLibraryBackup {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let total = try BackupArchiveIO.size(source)
        guard try BackupArchiveIO.exact(input, count: 8) == BackupArchiveIO.magic else { throw LibraryBackupError.invalidArchive }
        let count = try BackupArchiveIO.number(input)
        guard count <= BackupArchiveIO.maximumManifest else { throw LibraryBackupError.tooLarge }
        let expected = try BackupArchiveIO.exact(input, count: 32)
        let metadata = try BackupArchiveIO.exact(input, count: Int(count))
        guard Data(SHA256.hash(data: metadata)) == expected else { throw LibraryBackupError.integrity }
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: metadata)
        try BackupValidation.manifest(manifest)
        let fileCount = try BackupArchiveIO.number(input)
        guard fileCount <= 200_000 else { throw LibraryBackupError.tooLarge }
        let assets = temporary.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        var paths = Set<String>(), normalizedPaths = Set<String>(), files: [BackupFile] = []
        for _ in 0..<fileCount {
            try Task.checkCancellation()
            let length = try BackupArchiveIO.number(input)
            guard length > 0, length <= 1024,
                  let path = String(data: try BackupArchiveIO.exact(input, count: Int(length)), encoding: .utf8)
            else { throw LibraryBackupError.unsafePath }
            try BackupValidation.path(path)
            guard paths.insert(path).inserted,
                  normalizedPaths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted
            else { throw LibraryBackupError.unsafePath }
            let size = try BackupArchiveIO.number(input), digest = try BackupArchiveIO.exact(input, count: 32)
            let offset = try input.offset()
            guard offset <= total, size <= total - offset else { throw LibraryBackupError.invalidArchive }
            let destination = assets.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let output = try BackupArchiveIO.create(destination)
            do {
                let actual = try BackupArchiveIO.copy(input, to: output, size: size)
                try output.close()
                guard actual == digest else { throw LibraryBackupError.integrity }
            } catch { try? output.close(); throw error }
            files.append(.init(path: path, size: size, digest: digest))
        }
        guard try input.offset() == total else { throw LibraryBackupError.invalidArchive }
        for path in try BackupValidation.requiredFiles(manifest) where !paths.contains(path) { throw LibraryBackupError.missingFile(path) }
        return .init(id: UUID(), directory: temporary, manifest: manifest, files: files)
    }

    private static func enumerate(_ root: URL) throws -> [BackupFile] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var failure: Error?
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                                            errorHandler: { _, error in failure = error; return false })
        else { throw CocoaError(.fileReadUnknown) }
        var files: [BackupFile] = [], normalized = Set<String>()
        for case let url as URL in iterator {
            try Task.checkCancellation()
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true else { throw LibraryBackupError.unsafePath }
            guard properties.isRegularFile == true else { continue }
            let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard components.starts(with: root.pathComponents) else { throw LibraryBackupError.unsafePath }
            let path = components.dropFirst(root.pathComponents.count).joined(separator: "/")
            try BackupValidation.path(path)
            guard normalized.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw LibraryBackupError.unsafePath }
            files.append(.init(path: path, size: try BackupArchiveIO.size(url), digest: Data()))
            guard files.count <= 200_000 else { throw LibraryBackupError.tooLarge }
        }
        if let failure { throw failure }
        return files.sorted { $0.path < $1.path }
    }
}
