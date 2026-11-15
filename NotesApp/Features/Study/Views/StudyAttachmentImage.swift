import SwiftUI

struct StudyAttachmentImage: View {
    let path: String
    var storage: DrawingStorage = .shared
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Captured note region") }
            else if failed { Label("Image unavailable. Your card and source link are preserved.", systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.secondary) }
            else { ProgressView("Loading note image…") }
        }
        .task(id: path) {
            image = nil; failed = false
            do {
                let data = try await storage.read(path)
                guard !Task.isCancelled else { return }
                image = UIImage(data: data); failed = image == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
