import XCTest

/// Uses real system drag gestures, including native destination routing at six favorites.
/// Creates its own notebook/profile through the UI; never clears an existing store.
@MainActor final class PaletteReplacementUITests: XCTestCase {
    func testToolbarDragReplacesTheChosenFavoriteWhenFull() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Back to Library"].waitForExistence(timeout: 3) {
            app.buttons["Back to Library"].tap()
        }
        let title = "Palette QA " + UUID().uuidString.prefix(6)
        let create = app.buttons["New Notebook"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), app.debugDescription)
        create.tap()
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title)
        app.buttons["Create"].tap()
        let notebook = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 5), app.debugDescription)
        notebook.tap()
        XCTAssertTrue(toolbarTool("Pen", in: app).waitForExistence(timeout: 10), app.debugDescription)
        if app.buttons["Show Quick Palette"].exists { app.buttons["Show Quick Palette"].tap() }
        let profileMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Palette profile and options:")).firstMatch
        XCTAssertTrue(profileMenu.waitForExistence(timeout: 5), app.debugDescription)
        profileMenu.tap()
        app.buttons["Manage Profiles"].tap()
        app.buttons["New Profile"].tap()
        let alert = app.alerts["New Palette Profile"]
        alert.textFields["Name"].typeText(title)
        alert.buttons["Save"].tap()
        app.buttons["Done"].tap()

        let favorites = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "palette.favorite."))
        XCTAssertEqual(favorites.count, 1)
        for tool in ["Pencil", "Highlighter", "Eraser", "Lasso", "Laser"] {
            let expected = favorites.count + 1
            toolbarTool(tool, in: app).press(forDuration: 0.7, thenDragTo: app.buttons["palette.append"])
            XCTAssertTrue(waitForCount(expected, in: favorites), app.debugDescription)
        }

        let ids = favorites.allElementsBoundByIndex.map(\.identifier)
        // Visit both rows and every individual destination. Stable IDs and unchanged siblings
        // catch accidental appends, reorders, and a parent drop target swallowing a cell drop.
        for index in 0..<6 {
            let previous = ids.map { app.buttons[$0].value as? String }
            let destination = app.buttons[ids[index]]
            let source = toolbarTool(index == 5 ? "Highlighter" : "Laser", in: app)
            let expected = index == 5 ? "Highlighter" : "Laser"
            source.press(forDuration: 0.7, thenDragTo: destination)
            let changed = NSPredicate { _, _ in (destination.value as? String)?.hasPrefix(expected) == true }
            expectation(for: changed, evaluatedWith: nil)
            waitForExpectations(timeout: 5)
            XCTAssertEqual(favorites.count, 6)
            XCTAssertEqual(favorites.allElementsBoundByIndex.map(\.identifier), ids)
            for other in ids.indices where other != index {
                XCTAssertEqual(app.buttons[ids[other]].value as? String, previous[other])
            }
        }
        // Drag directly out of each grouped popover, including non-ink configurations.
        for (group, tool, slot) in [("Study Tools", "Sticky Note", 0), ("Study Tools", "Stamp", 1),
                                   ("Draw and Measure", "Rectangle", 2)] {
            app.buttons[group].tap()
            let source = toolbarTool(tool, in: app)
            XCTAssertTrue(source.waitForExistence(timeout: 5), app.debugDescription)
            let destination = app.buttons[ids[slot]]
            source.press(forDuration: 0.7, thenDragTo: destination)
            let changed = NSPredicate { _, _ in (destination.value as? String)?.hasPrefix(tool) == true }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5), .completed,
                           app.debugDescription)
            XCTAssertEqual(favorites.count, 6)
            XCTAssertEqual(favorites.allElementsBoundByIndex.map(\.identifier), ids)
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            destination.tap()
            XCTAssertTrue((destination.value as? String)?.hasPrefix(tool) == true)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Six favorites after individually targeted replacements"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitForCount(_ count: Int, in query: XCUIElementQuery) -> Bool {
        let predicate = NSPredicate { _, _ in query.count == count }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
    }

    private func toolbarTool(_ title: String, in app: XCUIApplication) -> XCUIElement {
        // Workspace's ancestor identifier propagates to toolbar descendants. Palette cells
        // have explicit IDs and can share a tool's label after saving/replacing a favorite.
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "palette.favorite.")).firstMatch
    }
}
