import SwiftUI
import PencilKit

struct PageThumbnail: View {
    let page: NotePage
    let notebookID: UUID
    let selected: Bool
    let storage: DrawingStorage
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.white
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                if failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            .frame(width: 60, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? AppTheme.accent : .gray.opacity(0.3), lineWidth: selected ? 3 : 1))
            Text("\(page.pageIndex + 1)").font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.pageIndex + 1), \(page.paperTemplate.title)\(failed ? ", unreadable drawing" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: page.updatedAt, priority: .utility) {
            do {
                let request = ThumbnailRequest(size: page.logicalSize, template: page.paperTemplate,
                                           drawingPath: page.drawingFilePath,
                                           fallbackPath: DrawingStorage.path(notebook: notebookID, page: page.id),
                                           pdfPath: page.pdfFilePath, pdfIndex: page.pdfPageIndex,
                                           pdfContentSize: page.contentSize, elements: try PageElementsCodec.decode(page.objectsData))
                let result = try await PageThumbnailService.shared.thumbnail(request, storage: storage)
                try Task.checkCancellation()
                image = result; failed = false
            } catch is CancellationError {
                // A disappearing/reused thumbnail must not install an old result or show a false error.
            } catch { image = nil; failed = true }
        }
    }
}
