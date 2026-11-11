import UIKit
import ImageIO

enum PageImageService {
    static func importImage(_ data: Data, notebookID: UUID, storage: DrawingStorage) async throws -> (String, CGSize) {
        let result = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2000
                  ] as CFDictionary), let encoded = UIImage(cgImage: cg).jpegData(compressionQuality: 0.88)
            else { throw PageElementError.unreadable }
            return (encoded, CGSize(width: cg.width, height: cg.height))
        }.value
        let path = "Notebooks/\(notebookID.uuidString)/Images/\(UUID().uuidString).jpg"
        try await storage.write(result.0, to: path)
        return (path, result.1)
    }
    static func load(_ elements: [PageElement], storage: DrawingStorage) async throws -> [String: UIImage] {
        try Task.checkCancellation()
        let paths = Set(elements.compactMap(\.imagePath))
        guard !paths.isEmpty else { return [:] }
        let worker = Task.detached(priority: .userInitiated) {
            var images: [String: UIImage] = [:]
            var preparationBudget = 24 * 1024 * 1024
            for path in paths.sorted() {
                try Task.checkCancellation()
                let data = try await storage.read(path)
                guard let image = UIImage(data: data) else { throw PageElementError.unreadable }
                // Predecode common images without eagerly expanding every photograph on a page.
                if let cg = image.cgImage, cg.width <= preparationBudget / 4 / max(1, cg.height) {
                    images[path] = image.preparingForDisplay() ?? image
                    preparationBudget -= cg.width * cg.height * 4
                } else { images[path] = image }
            }
            return images
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}
