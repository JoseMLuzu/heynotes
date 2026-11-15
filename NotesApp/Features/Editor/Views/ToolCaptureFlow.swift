import SwiftUI
import UniformTypeIdentifiers

struct ToolCapturePresentation: Identifiable {
    let snapshot: CapturedPage
    let region: CGRect
    let startsWithCard: Bool
    var id: UUID { snapshot.id }
}

struct ToolCaptureFlow: View {
    let presentation: ToolCapturePresentation
    let session: EditorSession
    @State private var cardMode: Bool
    init(presentation: ToolCapturePresentation, session: EditorSession) {
        self.presentation = presentation; self.session = session
        _cardMode = State(initialValue: presentation.startsWithCard)
    }
    var body: some View {
        if cardMode {
            RegionFlashcardForm(snapshot: presentation.snapshot, initialRegion: presentation.region,
                                container: session.context.container, storage: session.storage)
        } else {
            RegionCapturePreview(snapshot: presentation.snapshot, region: presentation.region, session: session) { cardMode = true }
        }
    }
}

private struct RegionCapturePreview: View {
    let snapshot: CapturedPage
    let region: CGRect
    let session: EditorSession
    let createCard: () -> Void
    @State private var png: Data?
    @State private var shared: SharedPDF?
    @State private var exportURL: URL?
    @State private var notice: String?
    @State private var error: String?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let png, let image = UIImage(data: png) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 480).accessibilityLabel("Captured region") }
                    else { ProgressView("Capturing region…") }
                    HStack {
                        Button("Copy Image", systemImage: "doc.on.doc") {
                            if let png { UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier); notice = "Copied" }
                        }
                        Button("Share", systemImage: "square.and.arrow.up") { Task { await share() } }
                    }.buttonStyle(.bordered).disabled(png == nil || working)
                    Button("Insert Copy on Page", systemImage: "photo.on.rectangle") {
                        guard let png else { return }
                        Task {
                            working = true; defer { working = false }
                            guard session.page?.id == snapshot.source.pageID else { error = "Return to the source page before inserting this capture."; return }
                            if await session.addImage(png) { dismiss() } else { error = session.errorMessage }
                        }
                    }.disabled(png == nil || working)
                    Button("Create Flashcard", systemImage: "rectangle.on.rectangle", action: createCard).disabled(png == nil || working)
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }.padding(24)
            }
            .navigationTitle("Region Capture").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) } }
            .studyError($error)
        }
        .appSheetPresentation().interactiveDismissDisabled(working)
        .task {
            do { png = try await PageCaptureService.shared.crop(snapshot.png, normalized: snapshot.normalized(region)) }
            catch { self.error = error.localizedDescription }
        }
        .sheet(item: $shared) { PDFShareSheet(url: $0.url) }
        .onDisappear { if let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) } }
    }
    private func share() async {
        guard let png else { return }
        working = true; defer { working = false }
        do {
            if exportURL == nil { exportURL = try await PageCaptureService.shared.shareFile(png) }
            if let exportURL { shared = SharedPDF(url: exportURL) }
        } catch { self.error = error.localizedDescription }
    }
}
