import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class PencilDoubleTapTests: XCTestCase {
    func testToolHistoryPreservesInkEraserAndManualSelections() throws {
        let suite = "PencilHistory.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tools = ToolPreferences(defaults: defaults)
        tools.selected = .marker; tools.ink.width = 24; tools.setColor(.orange)
        let marker = tools.ink
        tools.eraserMode = .precise; tools.eraserWidth = 30
        tools.toggleEraser()
        XCTAssertEqual(tools.selected, .eraser)
        XCTAssertEqual((tools.tool as? PKEraserTool)?.eraserType, .fixedWidthBitmap)
        tools.toggleEraser()
        XCTAssertEqual(tools.selected, .marker); XCTAssertEqual(tools.ink, marker)
        tools.selected = .pencil; tools.setColor(.blue)
        let pencil = tools.ink
        tools.selectPreviousTool()
        XCTAssertEqual(tools.selected, .marker); XCTAssertEqual(tools.ink, marker)
        tools.selectPreviousTool()
        XCTAssertEqual(tools.selected, .pencil); XCTAssertEqual(tools.ink, pencil)
        tools.selected = .objects; tools.toggleEraser(); tools.toggleEraser()
        XCTAssertEqual(tools.selected, .objects)
        tools.selectInkToolForColors()
        XCTAssertEqual(tools.selected, .pencil); XCTAssertEqual(tools.ink, pencil)
        XCTAssertEqual(ToolPreferences(defaults: defaults).ink, pencil)
    }

    func testSystemActionsRouteToExistingControlsAndDisabledActionDoesNothing() throws {
        let suite = "PencilActions.\(UUID())"
        let defaults = try XCTUnwrap(FluidityDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controls = EditorControlPreferences(defaults: defaults, palette: nil)
        let writes = defaults.dataWrites
        XCTAssertNil(controls.performPencilAction(.ignore))
        XCTAssertEqual(defaults.dataWrites, writes)
        XCTAssertEqual(controls.performPencilAction(.switchEraser), .toolChanged)
        XCTAssertEqual(controls.tools.selected, .eraser)
        XCTAssertEqual(controls.performPencilAction(.switchPrevious), .toolChanged)
        XCTAssertEqual(controls.tools.selected, .pen)
        controls.tools.selected = .eraser
        XCTAssertEqual(controls.performPencilAction(.showInkAttributes), .toolOptions)
        XCTAssertEqual(controls.tools.selected, .eraser)
        XCTAssertEqual(controls.performPencilAction(.showColorPalette), .toolOptions)
        XCTAssertEqual(controls.tools.selected, .pen)
        if #available(iOS 17.5, *) {
            XCTAssertEqual(controls.performPencilAction(.showContextualPalette), .contextualPalette)
            let currentWrites = defaults.dataWrites
            XCTAssertNil(controls.performPencilAction(.runSystemShortcut))
            XCTAssertEqual(defaults.dataWrites, currentWrites)
        }
    }

    func testNativeInteractionUpdatesCanvasAndFocusPopoverWithoutLosingInkOrUndo() async throws {
        let animations = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animations) }
        let suite = "PencilNative.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controls = EditorControlPreferences(defaults: defaults, palette: nil)
        controls.tools.selected = .marker
        controls.tools.ink.width = 24
        let marker = controls.tools.ink
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Pencil"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: DrawingStorage(root: root))
        await session.open(page)
        let points = [CGPoint(x: 40, y: 80), CGPoint(x: 240, y: 180)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        session.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue),
            path: PKStrokePath(controlPoints: points, creationDate: .now))])
        let original = session.drawing
        let focus = EditorFocusMode()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(rootView: EditorView(session: session, onLibrary: {}, focusMode: focus,
            preferencesDefaults: defaults, controls: controls).modelContainer(container))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        try await settle(host.view)
        let canvas = try XCTUnwrap(session.canvas)
        canvas.undoManager?.registerUndo(withTarget: canvas) { $0.drawing = PKDrawing() }
        let interaction = try XCTUnwrap(descendants(host.view).flatMap(\.interactions).compactMap { $0 as? UIPencilInteraction }.first)
        let delegate = try XCTUnwrap(interaction.delegate as? PencilDoubleTapCoordinator)
        XCTAssertTrue(interaction.isEnabled)
        delegate.receiveTap(.switchEraser)
        try await settle(host.view)
        XCTAssertEqual(controls.tools.selected, .eraser)
        XCTAssertTrue(canvas.tool is PKEraserTool)
        delegate.receiveTap(.switchEraser)
        try await settle(host.view)
        XCTAssertEqual(controls.tools.selected, .marker); XCTAssertEqual(controls.tools.ink, marker)
        XCTAssertEqual((canvas.tool as? PKInkingTool)?.inkType, .marker)
        XCTAssertTrue(session.canvas === canvas)
        XCTAssertEqual(canvas.drawing, original); XCTAssertEqual(session.drawing, original)
        XCTAssertEqual(canvas.undoManager?.canUndo, true)
        session.busy = true
        delegate.receiveTap(.switchEraser)
        XCTAssertEqual(controls.tools.selected, .marker)
        session.busy = false
        try await settle(host.view)
        delegate.receiveTap(.showColorPalette)
        try await settle(host.view)
        XCTAssertNotNil(host.presentedViewController)
        delegate.receiveTap(.showColorPalette)
        try await settle(host.view)
        for _ in 0..<20 {
            if host.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(host.presentedViewController)
        focus.enter()
        try await settle(host.view)
        delegate.receiveTap(.showColorPalette)
        try await settle(host.view)
        XCTAssertNotNil(host.presentedViewController)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Pencil-DoubleTap-Focus-Options"; attachment.lifetime = .keepAlways; add(attachment)
        delegate.receiveTap(.showColorPalette)
        try await settle(host.view)
        interaction.isEnabled = false
        delegate.receiveTap(.switchEraser)
        XCTAssertEqual(controls.tools.selected, .marker)
        delegate.detach()
        XCTAssertNil(interaction.view)
        XCTAssertEqual(canvas.drawing, original)
        withExtendedLifetime(container) {}
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
    private func settle(_ view: UIView) async throws {
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        view.layoutIfNeeded()
    }
}
