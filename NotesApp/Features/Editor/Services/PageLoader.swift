import PencilKit
import UIKit

struct PageLoadRequest: Sendable {
    let drawingPath: String?
    let fallbackDrawingPath: String
    let pdfPath: String?
    let pdfIndex: Int?
    var resolvedDrawingPath: String { drawingPath ?? fallbackDrawingPath }
}

struct LoadedNotePage: Sendable {
    let drawing: PKDrawing
    let background: UIImage?
}

/// Only immutable paths cross tasks. No SwiftData model or live canvas leaves MainActor.
enum PageLoader {
    static func elements(_ data: Data?) async throws -> [PageElement] {
        try Task.checkCancellation()
        guard let data else { return [] }
        let decoder = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try PageElementsCodec.decode(data)
        }
        return try await withTaskCancellationHandler {
            let result = try await decoder.value
            try Task.checkCancellation()
            return result
        } onCancel: { decoder.cancel() }
    }
    static func load(_ request: PageLoadRequest, storage: DrawingStorage) async throws -> LoadedNotePage {
        async let drawing = loadDrawing(request, storage: storage)
        async let background = loadBackground(request, storage: storage)
        return try await LoadedNotePage(drawing: drawing, background: background)
    }
    private static func loadDrawing(_ request: PageLoadRequest, storage: DrawingStorage) async throws -> PKDrawing {
        try Task.checkCancellation()
        if request.drawingPath == nil {
            guard try await storage.exists(request.fallbackDrawingPath) else { return PKDrawing() }
        }
        let data = try await storage.read(request.resolvedDrawingPath)
        let decoder = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try PKDrawing(data: data)
        }
        return try await withTaskCancellationHandler {
            let result = try await decoder.value
            try Task.checkCancellation()
            return result
        } onCancel: { decoder.cancel() }
    }
    private static func loadBackground(_ request: PageLoadRequest, storage: DrawingStorage) async throws -> UIImage? {
        guard let path = request.pdfPath else { return nil }
        guard let index = request.pdfIndex else { throw DocumentError.invalidPage }
        return try await PDFDocumentService.shared.background(path: path, index: index, storage: storage)
    }
}
