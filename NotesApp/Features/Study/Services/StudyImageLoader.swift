import UIKit
import ImageIO

/// Display-only images: decode/downsample on this worker, not during a card's SwiftUI render.
actor StudyImageLoader {
    static let shared = StudyImageLoader()
    private struct Key: Hashable { let source: FileFingerprint; let pixels: Int }
    private var images: CostLimitedCache<Key, UIImage>
    private var generation = 0
    private var decodes = 0, hits = 0, mainThreadDecodes = 0

    init(byteLimit: Int = 16 * 1024 * 1024) {
        images = CostLimitedCache(costLimit: max(0, byteLimit), countLimit: 32)
    }
    struct Statistics: Sendable {
        let decodes: Int; let hits: Int; let imageBytes: Int; let imageCount: Int; let mainThreadDecodes: Int
    }
    func statistics() -> Statistics {
        Statistics(decodes: decodes, hits: hits, imageBytes: images.totalCost, imageCount: images.count,
                   mainThreadDecodes: mainThreadDecodes)
    }
    func clearCache() { generation &+= 1; images.removeAll() }

    func image(path: String, storage: DrawingStorage, maxPixels: Int) async throws -> UIImage {
        try Task.checkCancellation()
        let cacheGeneration = generation
        let url = try await storage.fileURL(for: path)
        let source = try FileFingerprint(url: url)
        let key = Key(source: source, pixels: min(2400, max(1, maxPixels)))
        try Task.checkCancellation()
        if let cached = images.value(for: key) { hits += 1; return cached }
        let decoded = try decode(url, pixels: key.pixels)
        try Task.checkCancellation()
        guard try FileFingerprint(url: url) == source else { throw CocoaError(.fileReadUnknown) }
        let image = UIImage(cgImage: decoded)
        if generation == cacheGeneration {
            images.insert(image, for: key, cost: decoded.bytesPerRow * decoded.height)
        }
        return image
    }

    /// Synchronous decoder work stays on this actor's executor. The thread counter is only
    /// diagnostic and samples this block, never an async task's thread before/after suspension.
    private func decode(_ url: URL, pixels: Int) throws -> CGImage {
        guard let input = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PageElementError.unreadable }
        decodes += 1
        if Thread.isMainThread { mainThreadDecodes += 1 }
        return image
    }
}
