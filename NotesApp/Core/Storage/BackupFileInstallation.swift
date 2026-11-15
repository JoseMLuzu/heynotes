import Foundation

enum BackupFileInstallation {
    static func install(_ prepared: PreparedLibraryBackup, at destination: URL) throws {
        let manager = FileManager.default, source = prepared.directory.appendingPathComponent("Assets", isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        for directory in [prepared.directory, source] {
            guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory
            else { throw LibraryBackupError.unsafePath }
        }
        var paths = Set<String>(), normalized = Set<String>()
        for file in prepared.files {
            try BackupValidation.path(file.path)
            guard paths.insert(file.path).inserted,
                  normalized.insert(file.path.precomposedStringWithCanonicalMapping.lowercased()).inserted
            else { throw LibraryBackupError.unsafePath }
            var component = source
            for name in file.path.split(separator: "/") {
                component.appendPathComponent(String(name))
                guard try manager.attributesOfItem(atPath: component.path)[.type] as? FileAttributeType != .typeSymbolicLink
                else { throw LibraryBackupError.unsafePath }
            }
            guard try BackupArchiveIO.size(component) == file.size else { throw LibraryBackupError.integrity }
            let handle = try FileHandle(forReadingFrom: component)
            defer { try? handle.close() }
            guard try BackupArchiveIO.copy(handle, to: nil, size: file.size) == file.digest else { throw LibraryBackupError.integrity }
        }
        guard try BackupValidation.requiredFiles(prepared.manifest).isSubset(of: paths) else { throw LibraryBackupError.invalidMetadata }
        try Task.checkCancellation()
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try manager.moveItem(at: source, to: destination) }
        catch { try? manager.removeItem(at: destination); throw error }
    }
}
