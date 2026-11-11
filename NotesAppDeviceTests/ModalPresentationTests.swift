import XCTest
import SwiftUI
import SwiftData
@testable import NotesApp

@MainActor private final class ModalTestState: ObservableObject {
    @Published var isPresented = false
}

@MainActor private struct ModalTestHost: View {
    @ObservedObject var state: ModalTestState
    let content: AnyView
    var body: some View {
        Color.clear.sheet(isPresented: $state.isPresented) { content }
    }
}

@MainActor final class ModalPresentationTests: XCTestCase {
    func testAppFormsOpenExpandedWithoutDraggingInPortrait() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Modal check"), page = NotePage(pageIndex: 0), folder = Folder(title: "Biology")
        container.mainContext.insert(notebook); container.mainContext.insert(page); container.mainContext.insert(folder)
        notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let name = "ModalTests.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let palette = QuickPalettePreferences(defaults: defaults), tools = ToolPreferences(defaults: defaults)
        let element = PageElement(kind: .text, rect: CGRect(x: 10, y: 10, width: 240, height: 180))
        let forms: [(String, AnyView)] = [
            ("New Notebook", AnyView(NotebookForm(folders: [folder], initialFolderID: nil) { _, _, _, _ in true })),
            ("Rename", AnyView(TitleForm(heading: "Rename", title: "Biology") { _ in true })),
            ("Folder Color", AnyView(FolderColorPicker(folder: folder) { _ in true })),
            ("Settings", AnyView(AppSettingsView())),
            ("Quick Palette", AnyView(PaletteManager(palette: palette, tools: tools))),
            ("Palette Profiles", AnyView(PaletteProfileManager(palette: palette, tools: tools))),
            ("Edit Favorite", AnyView(ToolPresetEditor(draft: tools.capturePreset()) { _ in true })),
            ("Text", AnyView(PageElementEditor(draft: element, pageSize: PageGeometry.size, save: { _ in true }, remove: nil))),
            ("Inserted Content", AnyView(InsertedContentView(session: session))),
            ("Handwriting Style", AnyView(HandwritingStyleView(session: session))),
            ("PDF Margin", AnyView(PDFMarginEditor(session: session)))
        ]
        for (title, view) in forms {
            try await verifyExpanded(view, name: title, size: CGSize(width: 820, height: 1180), capture: title == "Settings" || title == "New Notebook")
        }
        withExtendedLifetime(container) {}
    }

    func testSettingsOpensExpandedInLandscapeAndNarrowWindow() async throws {
        for size in [CGSize(width: 1180, height: 820), CGSize(width: 540, height: 820)] {
            try await verifyExpanded(AnyView(AppSettingsView()), name: "Settings-\(Int(size.width))", size: size, capture: true)
        }
    }

    private func verifyExpanded(_ content: AnyView, name: String, size: CGSize, capture: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let state = ModalTestState(), host = UIHostingController(rootView: ModalTestHost(state: state, content: content))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        state.isPresented = true
        for _ in 0..<100 {
            if host.presentedViewController?.view.window != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let presented = try XCTUnwrap(host.presentedViewController, name)
        try await Task.sleep(for: .milliseconds(450))
        presented.view.layoutIfNeeded()
        let frame = presented.view.convert(presented.view.bounds, to: window)
        XCTAssertGreaterThan(frame.height, window.bounds.height * 0.80,
                             "\(name) opened too short: \(frame), available \(window.bounds)")
        XCTAssertLessThanOrEqual(frame.maxY, window.bounds.maxY + 1, "\(name) extends below the window")
        if capture {
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "Expanded-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        state.isPresented = false
        host.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(80))
    }
}
