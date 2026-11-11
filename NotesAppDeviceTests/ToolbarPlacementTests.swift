import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class ToolbarPlacementTests: XCTestCase {
    private var containers: [ModelContainer] = []
    func testPositionsPersistAndInvalidPreferencesFallBackToTop() throws {
        let name = "ToolbarPlacement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(EditorToolbarPreferences(defaults: defaults).position, .top)
        let preferences = EditorToolbarPreferences(defaults: defaults)
        for position in EditorToolbarPosition.allCases {
            preferences.position = position
            XCTAssertEqual(EditorToolbarPreferences(defaults: defaults).position, position)
            XCTAssertNotNil(UIImage(systemName: position.symbol))
        }
        defaults.set("unknown-future-position", forKey: EditorToolbarPreferences.key)
        XCTAssertEqual(EditorToolbarPreferences(defaults: defaults).position, .top)
    }

    func testAllEdgesKeepCanvasInkAndUndoAcrossRotation() async throws {
        let name = "ToolbarPlacement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let placement = EditorToolbarPreferences(defaults: defaults)
        let container = try PersistenceController.makeContainer(inMemory: true)
        containers.append(container)
        let notebook = Notebook(title: "Movable tools"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page)
        let points = [CGPoint(x: 80, y: 140), CGPoint(x: 260, y: 210)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        session.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue),
                                                      path: PKStrokePath(controlPoints: points, creationDate: .now))])
        let ink = session.drawing
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: EditorView(session: session, onLibrary: {}, toolbarPlacement: placement))
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let canvas = try XCTUnwrap(session.canvas)
        var text = PageElement(kind: .text, rect: CGRect(x: 100, y: 300, width: 250, height: 80))
        text.text = "Keep my undo history"
        XCTAssertTrue(session.insertElement(text))
        for size in [CGSize(width: 1180, height: 820), CGSize(width: 820, height: 1180)] {
            for position in EditorToolbarPosition.allCases {
                placement.position = position
                window.frame = CGRect(origin: .zero, size: size)
                host.view.frame = window.bounds; host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                host.view.layoutIfNeeded()
                XCTAssertTrue(session.canvas === canvas, "Moving tools must not reconstruct PencilKit.")
                XCTAssertEqual(canvas.drawing, ink)
                XCTAssertTrue(canvas.undoManager?.canUndo == true)
                XCTAssertEqual(session.elements, [text])
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Toolbar-\(position.rawValue)-\(Int(size.width))"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        canvas.undoManager?.undo()
        XCTAssertTrue(session.elements.isEmpty)
        XCTAssertEqual(canvas.drawing, ink)
    }
}
