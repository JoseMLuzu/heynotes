import XCTest
import SwiftUI
import PencilKit
@testable import NotesApp

@MainActor final class QuickPaletteTests: XCTestCase {
    func testToolbarRestoresHiddenAndCollapsedPaletteAfterRelaunch() throws {
        let suite = "QuickPaletteRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = QuickPalettePreferences(defaults: defaults)
        palette.place(PalettePosition(x: 0.8, y: 0.6))
        palette.isCollapsed = true; palette.isVisible = false
        let favorites = palette.favorites
        let reopened = QuickPalettePreferences(defaults: defaults)
        XCTAssertFalse(reopened.isVisible); XCTAssertTrue(reopened.isCollapsed)
        reopened.togglePresentation()
        XCTAssertTrue(reopened.isVisible); XCTAssertFalse(reopened.isCollapsed)
        XCTAssertEqual(reopened.favorites, favorites)
        XCTAssertEqual(reopened.position, PalettePosition(x: 0.8, y: 0.6))
        reopened.togglePresentation()
        XCTAssertFalse(reopened.isVisible)
        reopened.show()
        reopened.isCollapsed = true
        reopened.togglePresentation()
        let restored = QuickPalettePreferences(defaults: defaults)
        XCTAssertTrue(restored.isVisible); XCTAssertFalse(restored.isCollapsed)
        XCTAssertEqual(restored.favorites, favorites)
    }

    func testSameToolFavoritesRestoreIndependentInkAndEraserConfigurations() throws {
        let suite = "QuickPaletteTools.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tools = ToolPreferences(defaults: defaults)
        let blue = ToolPreset(name: "Blue", tool: .pen, ink: InkStyle(red: 0.1, green: 0.3, blue: 0.9, width: 2, opacity: 0.6))
        let red = ToolPreset(name: "Red", tool: .pen, ink: InkStyle(red: 0.8, green: 0.1, blue: 0.1, width: 5))
        tools.apply(blue)
        XCTAssertTrue(tools.matches(blue)); XCTAssertFalse(tools.matches(red))
        tools.apply(red)
        XCTAssertEqual((tools.tool as? PKInkingTool)?.width, 5)
        XCTAssertEqual(tools.ink, red.ink)
        tools.apply(blue)
        XCTAssertEqual(tools.ink, blue.ink)
        tools.ink.width = 4
        XCTAssertFalse(tools.matches(blue)) // Editing the top toolbar does not edit the favorite.
        XCTAssertEqual(blue.ink.width, 2)
        tools.apply(blue)
        let precise = ToolPreset(name: "Precise", tool: .eraser, eraserMode: .precise, eraserWidth: 30)
        tools.apply(precise)
        XCTAssertTrue(tools.matches(precise))
        XCTAssertEqual((tools.tool as? PKEraserTool)?.eraserType, .fixedWidthBitmap)
        XCTAssertEqual((tools.tool as? PKEraserTool)?.width, 30)
        let captured = tools.capturePreset(name: "Copied eraser")
        XCTAssertEqual(captured.eraserMode, .precise)
        XCTAssertEqual(captured.eraserWidth, 30)
        let reopened = ToolPreferences(defaults: defaults)
        XCTAssertTrue(reopened.matches(precise))
        reopened.apply(blue)
        XCTAssertEqual(reopened.ink, blue.ink)
    }

    func testFavoritesEditsOrderingLimitsAndPositionPersist() throws {
        let suite = "QuickPaletteState.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = QuickPalettePreferences(defaults: defaults)
        XCTAssertEqual(palette.favorites.count, 5)
        let first = try XCTUnwrap(palette.favorites.first)
        var draft = first; draft.name = "Edited"; draft.ink.width = 500
        XCTAssertEqual(palette.favorites.first, first) // A cancelled draft is isolated.
        XCTAssertTrue(palette.save(draft))
        XCTAssertEqual(palette.favorites.first?.id, first.id)
        XCTAssertEqual(palette.favorites.first?.ink.width, ToolPreset.widthRange(for: .pen).upperBound)
        let extra = ToolPreset(name: "Selection", tool: .lasso)
        XCTAssertTrue(palette.save(extra))
        XCTAssertFalse(palette.save(ToolPreset(name: "Seventh", tool: .pen)))
        palette.move(from: IndexSet(integer: 5), to: 0)
        XCTAssertEqual(palette.favorites.first?.id, extra.id)
        palette.remove(first.id)
        palette.place(PalettePosition(x: 0.7, y: 0.8))
        palette.isCollapsed = true; palette.isVisible = false
        let reopened = QuickPalettePreferences(defaults: defaults)
        XCTAssertEqual(reopened.favorites, palette.favorites)
        XCTAssertEqual(reopened.position, PalettePosition(x: 0.7, y: 0.8))
        XCTAssertTrue(reopened.isCollapsed); XCTAssertFalse(reopened.isVisible)
        for favorite in reopened.favorites { reopened.remove(favorite.id) }
        XCTAssertEqual(reopened.favorites.count, 1)
        reopened.place(PalettePosition(x: -.infinity, y: 99))
        XCTAssertEqual(reopened.position, PalettePosition(x: 0, y: 1))
    }

    func testViewportRotationClampingSnappingAndNativePaletteRendering() async throws {
        let size = QuickPaletteLayout.expandedSize(favorites: 6)
        for viewport in [CGSize(width: 1024, height: 680), CGSize(width: 680, height: 1024), CGSize(width: 320, height: 240)] {
            for position in [PalettePosition(x: 0, y: 0), PalettePosition(x: 1, y: 1), PalettePosition(x: 0.6, y: 0.4)] {
                let origin = PalettePlacement.origin(position, palette: size, viewport: viewport)
                XCTAssertGreaterThanOrEqual(origin.x, 0); XCTAssertGreaterThanOrEqual(origin.y, 0)
                XCTAssertLessThanOrEqual(origin.x + size.width, viewport.width)
                XCTAssertLessThanOrEqual(origin.y + size.height, viewport.height)
                let roundTrip = PalettePlacement.position(for: origin, palette: size, viewport: viewport, snap: false)
                XCTAssertEqual(roundTrip.x, position.x, accuracy: 0.0001)
                XCTAssertEqual(roundTrip.y, position.y, accuracy: 0.0001)
            }
            let clamped = PalettePlacement.clamped(CGPoint(x: -100, y: 10000), palette: size, viewport: viewport)
            XCTAssertEqual(PalettePlacement.position(for: clamped, palette: size, viewport: viewport), PalettePosition(x: 0, y: 1))
            let nearEdge = CGPoint(x: 18, y: 18)
            XCTAssertEqual(PalettePlacement.position(for: nearEdge, palette: size, viewport: viewport), PalettePosition(x: 0, y: 0))
        }
        let suite = "QuickPaletteRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = QuickPalettePreferences(defaults: defaults), tools = ToolPreferences(defaults: defaults)
        tools.apply(try XCTUnwrap(palette.favorites.first))
        let view = QuickPalette(palette: palette, tools: tools, canInteract: { true })
            .frame(width: 360, height: 300).background(Color(white: 0.94)).environment(\.colorScheme, .light)
        // ImageRenderer cannot render UIViewRepresentable or native Menu controls.
        // Host in a real test window so the snapshot also includes the finger-only grip.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        await Task.yield()
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        let image = renderer.image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Quick-Palette"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
