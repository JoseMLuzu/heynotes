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

}
