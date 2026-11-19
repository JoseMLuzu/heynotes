import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class ToolbarOrganizationTests: XCTestCase {
    private var containers: [ModelContainer] = []

    func testEveryToolHasExactlyOneVisibleHomeAndPDFAvailabilityIsContextual() throws {
        let direct: [EditorTool] = [.pen, .pencil, .marker, .eraser, .lasso, .objects, .laser, .writingZoom]
        let grouped = ToolbarToolGroup.allCases.flatMap(\.tools)
        XCTAssertEqual(Set(direct + grouped), Set(EditorTool.allCases), "A newly added tool must have a discoverable toolbar home.")
        XCTAssertEqual(direct.count + grouped.count, Set(direct + grouped).count, "Tools must not be duplicated across groups.")
        let note = NotePage(pageIndex: 0), pdf = NotePage(pageIndex: 1)
        pdf.pdfFilePath = "Sources/lecture.pdf"; pdf.pdfPageIndex = 0
        XCTAssertFalse(ToolbarToolGroup.isAvailable(.pdfHighlight, on: note))
        XCTAssertFalse(ToolbarToolGroup.isAvailable(.pdfHighlight, on: nil))
        XCTAssertTrue(ToolbarToolGroup.isAvailable(.pdfHighlight, on: pdf))
        for tool in grouped where tool != .pdfHighlight { XCTAssertTrue(ToolbarToolGroup.isAvailable(tool, on: note)) }
    }

    func testNamedGroupPanelsAndSelectionsKeepNativeCanvasAndUndo() async throws {
        let suite = "ToolbarGroups.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.makeContainer(inMemory: true); containers.append(container)
        let book = Notebook(title: "Discoverable tools"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = EditorSession(notebook: book, context: container.mainContext, storage: DrawingStorage(root: root))
        await session.open(page); defer { session.discardPreparedPages() }
        let controls = EditorControlPreferences(defaults: defaults, palette: nil)
        controls.palette.isVisible = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: EditorView(session: session, onLibrary: {}, controls: controls, showsWorkspaceTabs: false))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        host.view.frame = window.bounds; host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(100))
        let canvas = try XCTUnwrap(session.canvas)
        var note = PageElement(kind: .text, rect: CGRect(x: 60, y: 80, width: 300, height: 100)); note.text = "Toolbar groups keep my work"
        XCTAssertTrue(session.insertElement(note))
        for tool in ToolbarToolGroup.allCases.flatMap(\.tools) + [.laser, .writingZoom, .pen] {
            controls.tools.selected = tool; host.view.layoutIfNeeded(); await Task.yield(); host.view.layoutIfNeeded()
            XCTAssertTrue(session.canvas === canvas); XCTAssertTrue(canvas.undoManager?.canUndo == true)
            XCTAssertEqual(session.elements, [note])
        }
        for size in [CGSize(width: 1180, height: 820), CGSize(width: 820, height: 1180)] {
            window.frame = CGRect(origin: .zero, size: size); host.view.frame = window.bounds
            host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(100)); host.view.layoutIfNeeded()
            capture(window, name: "Organized-Toolbar-\(Int(size.width))")
        }
        for group in ToolbarToolGroup.allCases {
            let panel = UIHostingController(rootView: ToolbarToolGroupPanel(group: group, preferences: controls.tools, page: page,
                palette: controls.palette, canInteract: { true }) { controls.tools.selected = $0 }.padding().background(AppTheme.background))
            window.frame = CGRect(x: 0, y: 0, width: 360, height: group == .drawing ? 520 : 380)
            window.rootViewController = panel; panel.view.frame = window.bounds; panel.view.layoutIfNeeded()
            await Task.yield(); capture(window, name: "Tool-Panel-\(group.rawValue)")
        }
        canvas.undoManager?.undo(); XCTAssertTrue(session.elements.isEmpty)
    }

    private func capture(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
