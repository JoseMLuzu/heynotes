import XCTest
import SwiftUI
import PencilKit
@testable import NotesApp

@MainActor final class QuickControlsTests: XCTestCase {
    func testFavoriteColorsReopenIndependentlyAndLegacyPreferencesStillDecode() throws {
        let suite = "QuickControls.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tools = ToolPreferences(defaults: defaults)
        tools.selected = .pen; tools.ink.width = 3.7; tools.ink.opacity = 0.45
        let pencilDefaults = QuickInkColor.defaults(for: .pencil)
        XCTAssertTrue(tools.setQuickColor(.purple, at: 0))
        let penColors = tools.quickColors
        tools.setColor(penColors[0].color)
        XCTAssertEqual(tools.ink.width, 3.7); XCTAssertEqual(tools.ink.opacity, 0.45)
        tools.selected = .pencil; XCTAssertEqual(tools.quickColors, pencilDefaults)
        XCTAssertTrue(tools.setQuickColor(.cyan, at: 1))
        let pencilColors = tools.quickColors
        tools.selected = .marker; XCTAssertTrue(tools.setQuickColor(.red, at: 2))
        let markerColors = tools.quickColors
        let restored = ToolPreferences(defaults: defaults)
        XCTAssertEqual(restored.quickColors, markerColors)
        restored.selected = .pencil; XCTAssertEqual(restored.quickColors, pencilColors)
        restored.selected = .pen; XCTAssertEqual(restored.quickColors, penColors)
        XCTAssertFalse(restored.setQuickColor(.green, at: 3))
        for tool in [EditorTool.pen, .pencil, .marker, .line, .arrow] {
            restored.selected = tool
            XCTAssertEqual(restored.quickWidths.count, 3)
            XCTAssertTrue(restored.quickWidths.allSatisfy { restored.widthRange.contains($0) })
        }
        restored.selected = .eraser; restored.eraserMode = .precise
        restored.eraserWidth = restored.quickEraserSizes[2]
        XCTAssertEqual(try XCTUnwrap(restored.tool as? PKEraserTool).width, CGFloat(restored.eraserWidth))
        XCTAssertFalse(restored.setQuickColor(.red, at: 0))
        restored.selected = .pen
        let data = try XCTUnwrap(defaults.data(forKey: "editor.tools.v1"))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["quickPenColors", "quickPencilColors", "quickMarkerColors"] { legacy.removeValue(forKey: key) }
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "editor.tools.v1")
        let oldArchive = ToolPreferences(defaults: defaults)
        XCTAssertEqual(oldArchive.ink.width, 3.7); XCTAssertEqual(oldArchive.ink.opacity, 0.45)
        XCTAssertEqual(oldArchive.quickColors, QuickInkColor.defaults(for: .pen))
    }

    func testObjectActionsKeepImageBytesIndependentMetadataAndUndoHistory() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let notebook = Notebook(title: "Objects"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext, storage: storage)
        await session.open(page)
        let canvas = InkCanvas(); canvas.pageID = page.id; session.canvas = canvas
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image {
            UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }.pngData()!
        let inserted = await session.addImage(data); XCTAssertTrue(inserted)
        var original = try XCTUnwrap(session.selectedElement)
        original.x = page.logicalSize.width - original.width
        original.y = page.logicalSize.height - original.height
        XCTAssertTrue(session.updateElement(original))
        let path = try XCTUnwrap(original.imagePath), bytes = try await storage.read(path)
        canvas.undoManager?.removeAllActions()
        XCTAssertTrue(session.duplicateElement(original.id))
        let copy = try XCTUnwrap(session.selectedElement)
        XCTAssertNotEqual(copy.id, original.id); XCTAssertEqual(copy.imagePath, path)
        XCTAssertLessThanOrEqual(copy.rect.maxX, page.logicalSize.width)
        XCTAssertLessThanOrEqual(copy.rect.maxY, page.logicalSize.height)
        canvas.undoManager?.undo(); XCTAssertEqual(session.elements, [original])
        canvas.undoManager?.redo(); XCTAssertEqual(session.elements.map(\.id), [original.id, copy.id])
        XCTAssertTrue(session.deleteElement(copy.id)); XCTAssertEqual(session.elements, [original])
        canvas.undoManager?.undo(); XCTAssertEqual(session.elements.map(\.id), [original.id, copy.id])
        XCTAssertFalse(session.deleteElement(UUID()))
        let retained = try await storage.read(path); XCTAssertEqual(retained, bytes)
        XCTAssertEqual(try PageElementsCodec.decode(page.objectsData).map(\.id), [original.id, copy.id])
        session.selectedElementID = original.id
        try attachContextControls(session)
    }

    private func attachContextControls(_ session: EditorSession) throws {
        let suite = "QuickControlsPreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tools = [EditorTool.pen, .marker, .eraser, .objects].map { tool in
            let preferences = ToolPreferences(defaults: defaults)
            preferences.selected = tool; preferences.eraserMode = .precise
            return preferences
        }
        let sheet = VStack(spacing: 12) {
            ForEach(tools.indices, id: \.self) { index in
                HStack {
                    Text(tools[index].selected.title).font(.caption).frame(width: 110, alignment: .leading)
                    ToolbarQuickControls(preferences: tools[index], session: session, inline: true, edit: { _ in })
                }
            }
        }.padding(20).background(Color(white: 0.08)).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: sheet); renderer.scale = 2
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "Quick-Adjustments-All-Contexts"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
