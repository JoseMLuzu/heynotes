import Foundation
import CryptoKit

/// Bounded streaming I/O. No PDF or drawing is loaded wholly into memory by the archive layer.
enum BackupArchiveIO {
    static let chunkSize = 1_048_576
    static let maximumManifest = 64 * 1_048_576
    static let magic = Data("HEYBKP01".utf8)

    static func integer(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    static func number(_ handle: FileHandle) throws -> UInt64 {
        let bytes = try exact(handle, count: 8)
        return bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
    }
    static func exact(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: min(chunkSize, count - result.count)), !data.isEmpty
            else { throw LibraryBackupError.invalidArchive }
            result.append(data)
        }
        return result
    }
    static func copy(_ source: FileHandle, to destination: FileHandle?, size: UInt64) throws -> Data {
        var remaining = size, hash = SHA256()
        while remaining > 0 {
            let data = try exact(source, count: Int(min(UInt64(chunkSize), remaining)))
            hash.update(data: data); try destination?.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
        return Data(hash.finalize())
    }
    static func create(_ url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        return try FileHandle(forWritingTo: url)
    }
    static func size(_ url: URL) throws -> UInt64 {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw LibraryBackupError.invalidArchive
        }
        return size.uint64Value
    }
    static func temporaryDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appendingPathComponent("HeyNotesBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    static func discardTemporary(_ root: URL) {
        let resolved = root.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent() == URL.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              resolved.lastPathComponent.hasPrefix("HeyNotesBackup-") else { return }
        try? FileManager.default.removeItem(at: resolved)
    }
}
