import SwiftUI

/// Read-only PDF artwork. Uses the thumbnail worker, separate from full-size editor rendering.
struct PDFDocumentCover: View {
    let path: String
    let pageIndex: Int?
    var favorite = false
    var storage: DrawingStorage = .shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    @State private var failed = false

    private struct Source: Hashable {
        let path: String
        let index: Int?
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: max(1, geometry.size.width - 16), height: max(1, geometry.size.height - 16))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.ellipsis").font(.title2)
                        Text("Preview unavailable").font(.caption).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary).padding(16)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    Text("PDF").font(.system(.caption2, weight: .semibold))
                    if favorite { Image(systemName: "star.fill").font(.caption2) }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule()).padding(10)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 8, x: 0, y: 5)
        }
        .aspectRatio(0.82, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PDF preview")
        .accessibilityValue(failed ? "Preview unavailable" : image == nil ? "Loading" : "Loaded")
        .task(id: Source(path: path, index: pageIndex), priority: .utility) {
            image = nil; failed = false
            do {
                guard let pageIndex else { throw DocumentError.invalidPage }
                let result = try await PDFDocumentService.thumbnails.background(
                    path: path, index: pageIndex, storage: storage, maxPixels: 640)
                try Task.checkCancellation()
                image = result
            } catch is CancellationError {
                // A reused/disappearing card must not show a stale result or a false error.
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
