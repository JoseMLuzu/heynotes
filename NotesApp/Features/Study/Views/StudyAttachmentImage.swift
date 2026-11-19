import SwiftUI

struct StudyAttachmentImage: View {
    let path: String
    var storage: DrawingStorage = .shared
    var maximumDimension: CGFloat = 900
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedImage?
    @State private var failedRequest: Request?
    private struct Request: Hashable { let path: String; let storage: ObjectIdentifier; let pixels: Int }
    private struct LoadedImage { let request: Request; let image: UIImage }
    private var request: Request {
        Request(path: path, storage: ObjectIdentifier(storage),
                pixels: Int(min(2400, max(1, maximumDimension * displayScale)).rounded(.up)))
    }
    var body: some View {
        let request = self.request
        Group {
            if let loaded, loaded.request == request { Image(uiImage: loaded.image).resizable().scaledToFit().accessibilityLabel("Captured note region") }
            else if failedRequest == request { Label("Image unavailable. Your card and source link are preserved.", systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.secondary) }
            else { ProgressView("Loading note image…") }
        }
        .task(id: request) {
            loaded = nil; failedRequest = nil
            do {
                let image = try await StudyImageLoader.shared.image(path: request.path, storage: storage, maxPixels: request.pixels)
                guard !Task.isCancelled else { return }
                loaded = LoadedImage(request: request, image: image)
            } catch { if !Task.isCancelled { failedRequest = request } }
        }
    }
}
