import XCTest
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class EditorMenuTests: XCTestCase {
    func testFiveTopLevelEntriesAndRelevantPageOptions() async throws {
        let fixture = try MenuFixture()
        defer { fixture.cleanup() }
        await fixture.session.open(fixture.first)
        let menu = fixture.menu().make()
        let top = menu.children.compactMap { $0 as? UIMenu }.flatMap(\.children)
        XCTAssertEqual(top.map(\.title), ["Add Page", "Focus Mode", "Export PDF", "Page", "Workspace"])
        let pageMenu = try XCTUnwrap(top.compactMap { $0 as? UIMenu }.first { $0.title == "Page" })
        XCTAssertTrue(pageMenu.children.contains { $0.title == "Page Template" })
        XCTAssertTrue(pageMenu.children.contains { $0.title == "Create Flashcard" })
        XCTAssertFalse(pageMenu.children.contains { $0.title == "PDF Note Margin" })
        XCTAssertFalse(allActions(menu).contains { $0.title == "Settings" || $0.title == "Ruler" })
        let workspace = try XCTUnwrap(top.compactMap { $0 as? UIMenu }.first { $0.title == "Workspace" })
        let palette = try XCTUnwrap(workspace.children.compactMap { $0 as? UIMenu }.first { $0.title == "Quick Palette" })
        fixture.palette.isVisible = false
        fixture.palette.place(PalettePosition(x: 1, y: 1))
        let restore = try XCTUnwrap(palette.children.compactMap { $0 as? UIAction }.first { $0.title == "Restore Position" })
        let button = UIButton(type: .system)
        button.addAction(restore, for: .primaryActionTriggered); button.sendActions(for: .primaryActionTriggered)
        XCTAssertTrue(fixture.palette.isVisible); XCTAssertEqual(fixture.palette.position, PalettePosition())
        fixture.first.pdfFilePath = "Sources/fixture.pdf"; fixture.first.pdfPageIndex = 0
        let pdfActions = allActions(fixture.menu().make())
        XCTAssertTrue(pdfActions.contains { $0.title == "PDF Note Margin" })
        XCTAssertFalse(pdfActions.contains { $0.title == "Page Template" })
    }

    func testPracticeExportOnlyAppearsForPagesWithStudyTape() async throws {
        let fixture = try MenuFixture()
        defer { fixture.cleanup() }
        await fixture.session.open(fixture.first)
        let plain = await fixture.menu().makeExportItems()
        XCTAssertEqual(plain.map(\.title), ["Current Page", "Entire Notebook"])
        let tape = PageElement(kind: .tape, rect: CGRect(x: 20, y: 20, width: 100, height: 40))
        fixture.second.objectsData = try PageElementsCodec.encode([tape])
        try fixture.container.mainContext.save()
        let otherPage = await fixture.menu().makeExportItems()
        let notebookPractice = try XCTUnwrap(otherPage.compactMap { $0 as? UIMenu }.first { $0.title == "Practice" })
        XCTAssertEqual(notebookPractice.children.map(\.title), ["Entire Notebook (Covered)"])
        XCTAssertTrue(fixture.session.insertElement(tape))
        let currentPage = await fixture.menu().makeExportItems()
        let practice = try XCTUnwrap(currentPage.compactMap { $0 as? UIMenu }.first { $0.title == "Practice" })
        XCTAssertEqual(practice.children.map(\.title), ["Current Page (Covered)", "Entire Notebook (Covered)"])
    }

    func testThumbnailOperationsTargetInactivePageAndRetainDrawingFiles() async throws {
        let fixture = try MenuFixture()
        defer { fixture.cleanup() }
        let firstID = fixture.first.id, secondID = fixture.second.id
        let fallback = DrawingStorage.path(notebook: fixture.notebook.id, page: secondID)
        let drawing = ink()
        try await fixture.session.storage.write(drawing.dataRepresentation(), to: fallback)
        await fixture.session.open(fixture.first)
        fixture.session.changed(drawing)
        await fixture.session.duplicatePage(fixture.second)
        let duplicate = try XCTUnwrap(fixture.session.page)
        XCTAssertNotEqual(duplicate.id, secondID)
        XCTAssertEqual(fixture.session.drawing.strokes.count, 1)
        XCTAssertNotEqual(duplicate.drawingFilePath, fallback)
        let duplicateID = duplicate.id
        await fixture.session.open(fixture.first)
        let canvas = InkCanvas(); canvas.pageID = firstID; canvas.drawing = drawing
        fixture.session.canvas = canvas
        fixture.session.movePage(-1, target: fixture.second)
        XCTAssertEqual(fixture.notebook.orderedPages.map(\.id), [secondID, firstID, duplicateID])
        XCTAssertEqual(fixture.session.page?.id, firstID)
        await fixture.session.deletePage(fixture.second)
        XCTAssertEqual(fixture.session.page?.id, firstID)
        XCTAssertTrue(fixture.session.canvas === canvas)
        XCTAssertEqual(canvas.drawing, drawing)
        let retained = try await fixture.session.storage.exists(fallback)
        XCTAssertTrue(retained)
        await fixture.session.deletePage(fixture.first)
        XCTAssertEqual(fixture.session.page?.id, duplicateID)
        XCTAssertEqual(fixture.session.drawing.strokes.count, 1)
        XCTAssertEqual(fixture.notebook.orderedPages.map(\.pageIndex), [0])
        await fixture.session.deletePage()
        XCTAssertEqual(fixture.notebook.pages.count, 1)
    }

    func testFailedSaveBlocksThumbnailDuplicationAndDeletion() async throws {
        let fixture = try MenuFixture(blockedStorage: true)
        defer { fixture.cleanup() }
        await fixture.session.open(fixture.first)
        fixture.session.changed(ink())
        await fixture.session.duplicatePage(fixture.second)
        XCTAssertEqual(fixture.notebook.pages.count, 2)
        await fixture.session.deletePage(fixture.second)
        XCTAssertEqual(fixture.notebook.pages.count, 2)
        XCTAssertTrue(fixture.session.hasPendingSave)
        XCTAssertEqual(fixture.session.page?.id, fixture.first.id)
        XCTAssertTrue(allActions(fixture.menu().make()).contains { $0.title == "Retry Saving" })
    }

    private func allActions(_ menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { element in
            if let action = element as? UIAction { return [action] }
            return (element as? UIMenu).map(allActions) ?? []
        }
    }
    private func ink() -> PKDrawing {
        let points = [CGPoint(x: 20, y: 40), CGPoint(x: 160, y: 100)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }
}

@MainActor private final class MenuFixture {
    let container: ModelContainer
    let notebook = Notebook(title: "Menu")
    let first = NotePage(pageIndex: 0), second = NotePage(pageIndex: 1)
    let session: EditorSession
    let defaults: UserDefaults
    let palette: QuickPalettePreferences
    private let suite = "CompactMenu.\(UUID())"
    private let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init(blockedStorage: Bool = false) throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        palette = QuickPalettePreferences(defaults: defaults)
        container.mainContext.insert(notebook); container.mainContext.insert(first); container.mainContext.insert(second)
        notebook.pages = [first, second]
        try container.mainContext.save()
        if blockedStorage { try Data().write(to: root) }
        session = EditorSession(notebook: notebook, context: container.mainContext, storage: DrawingStorage(root: root))
    }
    func menu() -> EditorPageMenu {
        EditorPageMenu(session: session, workspace: nil, palette: palette,
                       placement: EditorToolbarPreferences(defaults: defaults), fingerDrawing: false,
                       setFingerDrawing: { _ in }, present: { _ in }, share: { _ in })
    }
    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
