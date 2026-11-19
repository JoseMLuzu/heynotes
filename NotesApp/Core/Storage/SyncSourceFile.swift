import Foundation
import CryptoKit
import Darwin

/// Read-only descriptor captured while editors are quiescent. Atomic replacements/removal of
/// the source path cannot change its inode. pread uses an independent offset for every copy.
final class SyncSourceFile: @unchecked Sendable {
    private let descriptor: Int32
    private let original: stat

    init(url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0 else {
            Darwin.close(descriptor); throw SyncUploadError.unsafePath
        }
        self.descriptor = descriptor; original = info
    }
    deinit { Darwin.close(descriptor) }

    func copy(to destination: URL) throws -> (String, UInt64) {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                              attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var hash = SHA256(), offset: Int64 = 0
        var buffer = Data(count: 1_048_576)
        while offset < original.st_size {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes {
                Darwin.pread(descriptor, $0.baseAddress, min($0.count, Int(original.st_size - offset)), off_t(offset))
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw SyncUploadError.changedSource }
            let chunk = buffer.prefix(count)
            hash.update(data: chunk); try output.write(contentsOf: chunk)
            offset += Int64(count)
        }
        var current = stat()
        guard fstat(descriptor, &current) == 0, current.st_size == original.st_size,
              current.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
              current.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec else { throw SyncUploadError.changedSource }
        try Task.checkCancellation(); try output.synchronize()
        return (hash.finalize().map { String(format: "%02x", $0) }.joined(), UInt64(offset))
    }
}

extension DrawingStorage {
    /// Call only inside the workspace's successful save/quiescence boundary. No bulk copy or
    /// hashing runs on the drawing-storage executor; descriptors retain the captured bytes.
    func captureSyncSources(_ plan: SyncUploadPlan) throws -> CapturedSyncUpload {
        guard plan.sources.count <= 256, Set(plan.sources.map(\.role)).count == plan.sources.count,
              (plan.metadata?.count ?? 0) <= 64 * 1_048_576 else { throw SyncUploadError.tooLarge }
        var files: [String: SyncSourceFile] = [:]
        var byPath: [String: SyncSourceFile] = [:]
        for source in plan.sources {
            try Task.checkCancellation()
            if let existing = byPath[source.path] { files[source.role] = existing; continue }
            let url = try fileURL(for: source.path)
            do {
                let file = try SyncSourceFile(url: url)
                files[source.role] = file; byPath[source.path] = file
            } catch let error as POSIXError where error.code == .ENOENT {
                guard source.allowsMissing else { throw SyncUploadError.missingAsset(source.role) }
            }
        }
        return CapturedSyncUpload(plan: plan, sources: files)
    }
}
