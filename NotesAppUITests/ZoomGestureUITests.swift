import XCTest

/// Real two-finger gestures: programmatic setZoomScale tests cannot detect a nested
/// PencilKit pinch recognizer competing with the page's recognizer.
@MainActor final class ZoomGestureUITests: XCTestCase {
    func testPinchKeepsPageMagnifiedAfterReleaseAndToolChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCUIDevice.shared.orientation = .portrait
        if app.buttons["Back to Library"].waitForExistence(timeout: 3) { app.buttons["Back to Library"].tap() }
        let create = app.buttons["New Notebook"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), app.debugDescription)
        create.tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let title = "Zoom QA " + UUID().uuidString.prefix(6)
        field.typeText(title); app.buttons["Create"].tap()
        let notebook = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 5)); notebook.tap()
        let viewport = app.scrollViews["editor.pageViewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 10), app.debugDescription)
        let pen = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "Pen", "palette.favorite.")).firstMatch
        XCTAssertTrue(pen.waitForExistence(timeout: 5))
        if !pen.isSelected { pen.tap() }
        let initial = try zoom(viewport)
        viewport.pinch(withScale: 3, velocity: 2)
        let first = try zoom(viewport)
        XCTAssertGreaterThan(first, initial * 1.15)
        // Tool updates and settling must not reset the magnification.
        let pencil = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "Pencil", "palette.favorite.")).firstMatch
        XCTAssertTrue(pencil.waitForExistence(timeout: 5)); pencil.tap()
        XCTAssertEqual(try zoom(viewport), first, accuracy: 2)
        var second = first
        // Synthesized pinches include UIKit's recognition threshold; their requested
        // scale is not an exact final zoom multiplier. Reach high zoom cumulatively.
        for _ in 0..<4 where second < 250 {
            viewport.pinch(withScale: 3, velocity: 1)
            let next = try zoom(viewport)
            XCTAssertGreaterThan(next, second * 1.1)
            second = next
        }
        XCTAssertGreaterThan(second, initial * 2.5)
        viewport.swipeUp(velocity: .slow)
        XCTAssertEqual(try zoom(viewport), second, accuracy: 2)
        for title in ["Page Options", "Workspace", "Draw with Finger"] {
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
            item.tap()
        }
        let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 14, dy: -8))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(try zoom(viewport), second, accuracy: 2)
        let undo = app.buttons["Undo"]
        let drew = NSPredicate { _, _ in undo.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: drew, object: nil)], timeout: 5), .completed,
                       "A small stroke must remain editable after real pinch zoom")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Stable page zoom after two finger pinches and pan"
        capture.lifetime = .keepAlways; add(capture)
    }
    private func zoom(_ viewport: XCUIElement) throws -> Double {
        let value = try XCTUnwrap(viewport.value as? String)
        return try XCTUnwrap(Double(value.replacingOccurrences(of: "%", with: "")))
    }
}
