import Foundation

/// All binary I/O is serialized off the main actor. Paths are relative to Documents.
public actor DrawingStorage {
    public static let shared = DrawingStorage()
    private let root: URL

    public init(root: URL = URL.documentsDirectory) { self.root = root }

    public nonisolated static func path(notebook: UUID, page: UUID) -> String {
        "Notebooks/\(notebook.uuidString)/Pages/\(page.uuidString).drawing"
    }

    private func url(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.isEmpty else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        var componentURL = root
        for component in path.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if let attributes = try? FileManager.default.attributesOfItem(atPath: componentURL.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        let result = root.appendingPathComponent(path).standardizedFileURL
        // Reject symlinks as well as lexical path traversal.
        let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
        guard result.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else {
            throw CocoaError(.fileReadNoPermission)
        }
        return result
    }

    public func fileURL(for path: String) throws -> URL { try url(path) }

    /// A coordinated file copy avoids loading an entire PDF into RAM. Never replaces originals.
    public func copyFile(from source: URL, to path: String) throws {
        let destination = try url(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Private immutable assets do not involve a file provider. Avoid coordinator IPC
        // when duplicating within our own storage root (and keep it for imported URLs).
        if source.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            do { try FileManager.default.copyItem(at: url, to: destination) }
            catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
    }

    public func read(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }
    public func exists(_ path: String) throws -> Bool { FileManager.default.fileExists(atPath: try url(path).path) }

    public func write(_ data: Data, to path: String) throws {
        let destination = try url(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the last valid checkpoint for recovery; a failed write never replaces the live file.
        if FileManager.default.fileExists(atPath: destination.path) {
            let manager = FileManager.default
            let backup = destination.appendingPathExtension("backup")
            let staged = destination.appendingPathExtension("checkpoint-\(UUID().uuidString).tmp")
            defer { try? manager.removeItem(at: staged) }
            // Copy file-to-file instead of allocating another complete PKDrawing Data buffer.
            try manager.copyItem(at: destination, to: staged)
            if manager.fileExists(atPath: backup.path) {
                _ = try manager.replaceItemAt(backup, withItemAt: staged)
            } else { try manager.moveItem(at: staged, to: backup) }
        }
        try data.write(to: destination, options: .atomic)
    }

    public func restoreBackup(_ path: String) throws -> Data {
        let live = try url(path)
        let backup = try Data(contentsOf: live.appendingPathExtension("backup"))
        // Preserve damaged bytes before attempting recovery.
        if FileManager.default.fileExists(atPath: live.path) {
            try Data(contentsOf: live).write(to: live.appendingPathExtension("damaged-\(UUID().uuidString)"), options: .atomic)
        }
        try backup.write(to: live, options: .atomic)
        return backup
    }
}
