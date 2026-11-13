import PencilKit
import UIKit

struct PagePreparationRequest: Hashable, Sendable {
    let pageID: UUID
    let source: PageLoadRequest
    let objectsData: Data?
}

struct PreparedPageContent: Sendable {
    let identity = UUID()
    let drawing: PKDrawing
    let background: UIImage?
    let elements: [PageElement]
    let images: [String: UIImage]
}

/// A bounded working set of decoded page values, never live canvases or SwiftData models.
actor PagePreparationService {
    typealias Loader = @Sendable (PagePreparationRequest, [PageElement], DrawingStorage) async throws -> PreparedPageContent
    private struct Sources: Hashable {
        let drawing: FileFingerprint?
        let pdf: FileFingerprint?
        let images: [FileFingerprint]
    }
    private struct Key: Hashable {
        let request: PagePreparationRequest
        let sources: Sources
    }
    private var pages: CostLimitedCache<Key, PreparedPageContent>
    private var metadata = CostLimitedCache<PagePreparationRequest, [PageElement]>(costLimit: 4 * 1024 * 1024, countLimit: 3)
    private struct Flight {
        let task: Task<PreparedPageContent, Error>
        var consumers: Set<UUID>
    }
    private var loading: [Key: Flight] = [:]
    private let loader: Loader
    private var generation = 0
    private var loads = 0
    private var hits = 0

    init(byteLimit: Int = 32 * 1024 * 1024, loader: @escaping Loader = PagePreparationService.loadPage) {
        pages = CostLimitedCache(costLimit: max(0, byteLimit), countLimit: 3)
        self.loader = loader
    }

    struct Statistics: Sendable {
        let loads: Int
        let hits: Int
        let cachedPages: Int
        let estimatedBytes: Int
        let consumers: Int
    }
    func statistics() -> Statistics {
        Statistics(loads: loads, hits: hits, cachedPages: pages.count, estimatedBytes: pages.totalCost,
                   consumers: loading.values.reduce(0) { $0 + $1.consumers.count })
    }

    func clear() {
        generation += 1
        pages.removeAll(); metadata.removeAll()
        // Foreground consumers may be waiting on these tasks. Let them finish, without recaching.
    }

    func content(_ request: PagePreparationRequest, storage: DrawingStorage, retry: Bool = true) async throws -> PreparedPageContent {
        try Task.checkCancellation()
        let cacheGeneration = generation
        let elements: [PageElement]
        if let existing = metadata.value(for: request) { elements = existing }
        else {
            elements = try await PageLoader.elements(request.objectsData)
            if cacheGeneration == generation {
                metadata.insert(elements, for: request, cost: request.objectsData?.count ?? 1)
            }
        }
        let version = try await sources(request, elements: elements, storage: storage)
        try Task.checkCancellation()
        let key = Key(request: request, sources: version)
        if let prepared = pages.value(for: key) { hits += 1; return prepared }
        let consumer = UUID()
        let task: Task<PreparedPageContent, Error>
        if var existing = loading[key] {
            task = existing.task
            existing.consumers.insert(consumer); loading[key] = existing
        }
        else {
            loads += 1
            task = Task { [loader] in try await loader(request, elements, storage) }
            loading[key] = Flight(task: task, consumers: [consumer])
        }
        do {
            let prepared = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.release(key, consumer: consumer, cancelIfUnused: true) }
            }
            try Task.checkCancellation()
            let current = try await sources(request, elements: elements, storage: storage)
            try Task.checkCancellation()
            guard current == version else {
                release(key, consumer: consumer, cancelIfUnused: false)
                guard retry else { throw CocoaError(.fileReadUnknown) }
                return try await content(request, storage: storage, retry: false)
            }
            if cacheGeneration == generation {
                let imageBytes = ([prepared.background].compactMap { $0 } + Array(prepared.images.values))
                    .reduce(0) { $0 + ($1.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) }
                let cost = imageBytes + (version.drawing?.bytes ?? 0) + (request.objectsData?.count ?? 0)
                pages.insert(prepared, for: key, cost: max(1, cost))
            }
            release(key, consumer: consumer, cancelIfUnused: false)
            return prepared
        } catch {
            release(key, consumer: consumer, cancelIfUnused: true)
            throw error
        }
    }

    private func release(_ key: Key, consumer: UUID, cancelIfUnused: Bool) {
        guard var flight = loading[key], flight.consumers.remove(consumer) != nil else { return }
        if flight.consumers.isEmpty {
            loading.removeValue(forKey: key)
            if cancelIfUnused { flight.task.cancel() }
        } else { loading[key] = flight }
    }

    static func loadPage(_ request: PagePreparationRequest, elements: [PageElement], storage: DrawingStorage) async throws -> PreparedPageContent {
        async let note = PageLoader.load(request.source, storage: storage)
        async let images = PageImageService.load(elements, storage: storage)
        let loaded = try await note
        return try await PreparedPageContent(drawing: loaded.drawing, background: loaded.background,
                                             elements: elements, images: images)
    }

    private func sources(_ request: PagePreparationRequest, elements: [PageElement], storage: DrawingStorage) async throws -> Sources {
        let drawingURL = try await storage.fileURL(for: request.source.resolvedDrawingPath)
        let drawing: FileFingerprint?
        if FileManager.default.fileExists(atPath: drawingURL.path) { drawing = try FileFingerprint(url: drawingURL) }
        else if request.source.drawingPath != nil { throw CocoaError(.fileNoSuchFile) }
        else { drawing = nil }
        let pdf: FileFingerprint?
        if let path = request.source.pdfPath { pdf = try FileFingerprint(url: await storage.fileURL(for: path)) }
        else { pdf = nil }
        var images: [FileFingerprint] = []
        for path in Set(elements.compactMap(\.imagePath)).sorted() {
            images.append(try FileFingerprint(url: await storage.fileURL(for: path)))
        }
        return Sources(drawing: drawing, pdf: pdf, images: images)
    }
}
