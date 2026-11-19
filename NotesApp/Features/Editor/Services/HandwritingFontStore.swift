import UIKit
import CoreText
import CryptoKit

struct HandwritingFontAsset: Identifiable, Sendable, Equatable {
    let name: String
    let title: String
    let path: String
    var id: String { name }
    var choice: HandwritingFont.Choice { .init(name: name, title: title) }
}

enum HandwritingFontError: LocalizedError {
    case invalid, tooLarge, conflictingName, missing
    var errorDescription: String? {
        switch self {
        case .invalid: "Choose a valid single-face TrueType (.ttf) or OpenType (.otf) font."
        case .tooLarge: "Choose a font smaller than 10 MB."
        case .conflictingName: "A different font with this internal name is already available. Use a font with a unique name."
        case .missing: "An imported font could not be loaded. Its reference and your original handwriting have been preserved."
        }
    }
}

/// Immutable user-owned font files. Parsing, file-provider coordination and registration
/// run on this actor; process registration is repeated after each application launch.
actor HandwritingFontStore {
    static let shared = HandwritingFontStore()
    private static let limit = 10 * 1024 * 1024
    private var registered: [String: String] = [:]
    private struct Cached {
        let size: Int
        let modified: Date
        let inode: UInt64
        let asset: HandwritingFontAsset
    }
    private var cache: [String: Cached] = [:]

    func importFont(from source: URL, storage: DrawingStorage) async throws -> HandwritingFontAsset {
        let ext = source.pathExtension.lowercased()
        guard ["ttf", "otf"].contains(ext) else { throw HandwritingFontError.invalid }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var bytes: Data?, failure: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            do { bytes = try Self.readBounded(url) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
        guard let bytes else { throw HandwritingFontError.invalid }
        let descriptor = try Self.describe(bytes, path: "") // Reject invalid files before copying anything.
        let digest = Self.digest(bytes)
        if UIFont(name: descriptor.name, size: 24) != nil, registered[descriptor.name] != digest {
            throw HandwritingFontError.conflictingName
        }
        let path = "Fonts/\(digest).\(ext)"
        if try await storage.exists(path) {
            guard try await storage.read(path) == bytes else { throw HandwritingFontError.invalid }
        } else { try await storage.write(bytes, to: path) }
        // A registration failure keeps the immutable copy for recovery; it never replaces another face.
        return try await load(path: path, storage: storage)
    }

    func catalog(storage: DrawingStorage, including references: [PageElement] = []) async throws -> [HandwritingFontAsset] {
        var paths = Set(references.compactMap(\.fontFilePath))
        // A portable restore keeps its own prefix. Visit only Fonts and Restored
        // directories, without walking every notebook image/PDF in a large library.
        var prefixes = [""]
        while let prefix = prefixes.popLast() {
            try Task.checkCancellation()
            let root = try await storage.fileURL(for: prefix + "Fonts")
            if FileManager.default.fileExists(atPath: root.path) {
                for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
                    paths.insert(prefix + "Fonts/\(url.lastPathComponent)")
                }
            }
            let restored = try await storage.fileURL(for: prefix + "Restored")
            if FileManager.default.fileExists(atPath: restored.path) {
                for url in try FileManager.default.contentsOfDirectory(at: restored, includingPropertiesForKeys: [.isDirectoryKey]) {
                    guard UUID(uuidString: url.lastPathComponent) != nil else { continue }
                    guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                    prefixes.append(prefix + "Restored/\(url.lastPathComponent)/")
                }
            }
        }
        var assets: [HandwritingFontAsset] = []
        for path in paths.sorted() { assets.append(try await load(path: path, storage: storage)) }
        var names = Set<String>()
        return assets.filter { names.insert($0.name).inserted }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func prepare(_ elements: [PageElement], storage: DrawingStorage) async throws {
        for path in Set(elements.compactMap(\.fontFilePath)) {
            let asset = try await load(path: path, storage: storage)
            guard elements.filter({ $0.fontFilePath == path }).allSatisfy({ $0.fontName == asset.name })
            else { throw HandwritingFontError.invalid }
        }
    }

    func load(path: String, storage: DrawingStorage) async throws -> HandwritingFontAsset {
        try Task.checkCancellation()
        guard ["ttf", "otf"].contains((path as NSString).pathExtension.lowercased()) else { throw HandwritingFontError.invalid }
        let url = try await storage.fileURL(for: path)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch { throw HandwritingFontError.missing }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? UInt64 else { throw HandwritingFontError.invalid }
        if let previous = cache[url.path], previous.size == size, previous.modified == modified, previous.inode == inode {
            return previous.asset
        }
        let data = try Self.readBounded(url)
        let asset = try Self.describe(data, path: path), digest = Self.digest(data)
        if let existing = registered[asset.name] {
            guard existing == digest else { throw HandwritingFontError.conflictingName }
        } else {
            // Never silently substitute a built-in face or a previously registered font.
            guard UIFont(name: asset.name, size: 24) == nil else { throw HandwritingFontError.conflictingName }
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
                if let error { throw error.takeRetainedValue() as Error }
                throw HandwritingFontError.invalid
            }
            registered[asset.name] = digest
        }
        guard UIFont(name: asset.name, size: 24) != nil else { throw HandwritingFontError.invalid }
        cache[url.path] = Cached(size: size, modified: modified, inode: inode, asset: asset)
        return asset
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw HandwritingFontError.tooLarge }
        guard !data.isEmpty else { throw HandwritingFontError.invalid }
        return data
    }

    private static func describe(_ data: Data, path: String) throws -> HandwritingFontAsset {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              descriptors.count == 1, let descriptor = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
              !name.isEmpty, name.count <= 128 else { throw HandwritingFontError.invalid }
        let title = (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? name
        return HandwritingFontAsset(name: name, title: title, path: path)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
