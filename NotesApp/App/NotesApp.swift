import SwiftUI

@main
struct NotesApp: App {
    private let startup: Result<AppDependencies, Error>

    init() {
        startup = Result {
            let dependencies = try AppDependencies()
            StudySampleDeck.createIfRequested(in: dependencies.container)
            return dependencies
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let dependencies):
                LibraryView(context: dependencies.container.mainContext)
                    .modelContainer(dependencies.container)
                    .modifier(AppAppearance())
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                        Task {
                            await PDFDocumentService.shared.clearCaches()
                            await PDFDocumentService.thumbnails.clearCaches()
                            await PageThumbnailService.shared.clearCache()
                        }
                    }
            case .failure(let error):
                ContentUnavailableView {
                    Label("Unable to Open Library", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved files have not been removed. Close and reopen the app. If the issue continues, keep the app installed to preserve your data.\n\n\(error.localizedDescription)")
                }
                .padding()
            }
        }
    }
}
