import Foundation
import CryptoKit
import Darwin

/// Synchronous helpers used only on the incoming actor. Never writes into Documents.
enum SyncIncomingFiles {
    private struct CheckedValue: Codable { let bytes: Data; let sha256: String }
    static let maximumManifestBytes: UInt64 = 2_097_152
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func check(_ url: URL, directory: Bool = false) throws {
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else { throw SyncIncomingError.unsafePath }
        let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        guard type == (directory ? .typeDirectory : .typeRegular) else { throw SyncIncomingError.unsafePath }
    }
    static func exists(_ url: URL) throws -> Bool {
        // Unlike fileExists, a dangling symlink must never masquerade as a missing file.
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return false }
    }
    static func read(_ url: URL, maximum: UInt64) throws -> Data {
        try check(url)
        let source = try SyncSourceFile(url: url)
        guard source.byteCount <= maximum else { throw SyncIncomingError.tooLarge }
        return try source.read(maximumBytes: maximum)
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(value)
        let data = try encoder.encode(CheckedValue(bytes: bytes, sha256: digest(bytes)))
        guard data.count <= maximumManifestBytes else { throw SyncIncomingError.tooLarge }
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.synchronize()
        try syncDirectory(url.deletingLastPathComponent())
    }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try read(url, maximum: maximumManifestBytes)
        do {
            let checked = try JSONDecoder().decode(CheckedValue.self, from: data)
            guard digest(checked.bytes) == checked.sha256 else { throw SyncIncomingError.integrity }
            return try JSONDecoder().decode(type, from: checked.bytes)
        } catch { throw SyncIncomingError.integrity }
    }
    static func verify(_ url: URL, hash: String, bytes: UInt64) throws {
        try check(url)
        let source = try SyncSourceFile(url: url)
        guard source.byteCount == bytes, bytes <= SyncCloudRecordPlan.maximumAssetBytes else { throw SyncIncomingError.integrity }
        let (actual, count) = try source.fingerprint()
        guard count == bytes, actual == hash else { throw SyncIncomingError.integrity }
    }

    static func install(_ source: SyncSourceFile, as url: URL, hash: String, bytes: UInt64) throws {
        if try exists(url) { try verify(url, hash: hash, bytes: bytes); return }
        let partial = url.deletingLastPathComponent().appendingPathComponent("partial-" + UUID().uuidString)
        // Partial files are deliberately retained on failure for explicit later recovery.
        let (actual, size) = try source.copy(to: partial)
        guard actual == hash, size == bytes else { throw SyncIncomingError.integrity }
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: partial.path)
        try FileManager.default.moveItem(at: partial, to: url)
        try syncDirectory(url.deletingLastPathComponent())
    }
    static func syncDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw SyncIncomingError.unsafePath }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
