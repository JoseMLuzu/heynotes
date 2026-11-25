import Foundation
import Darwin

/// One writer even across actor instances/processes. The descriptor is closed once,
/// under a lock, so explicit close and deinitialization can safely share release().
final class SyncStateDirectory: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var descriptor: Int32

    init(_ directory: URL) throws {
        let directory = directory.standardizedFileURL
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw SyncStateError.unsafePath }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let file = directory.appendingPathComponent("writer.lock")
        let fd = Darwin.open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw SyncStateError.unsafePath }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(fd); throw SyncStateError.unsafePath
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); throw SyncStateError.alreadyOpen }
        url = directory; descriptor = fd
        do {
            for suffix in ["", "-wal", "-shm"] {
                let path = directory.appendingPathComponent("State.sqlite" + suffix)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: path.path) {
                    guard attributes[.type] as? FileAttributeType == .typeRegular,
                          path.resolvingSymlinksInPath().path == path.path else { throw SyncStateError.unsafePath }
                }
            }
        } catch { release(); throw error }
    }

    func release() {
        lock.withLock {
            if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        }
    }
    deinit { release() }
}
