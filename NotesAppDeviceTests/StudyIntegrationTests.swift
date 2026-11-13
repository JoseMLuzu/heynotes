import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class StudyIntegrationTests: XCTestCase {
    func testFullyReviewedDeckCanPracticeAllAgainWithoutChangingReviewHistory() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = StudyViewModel(container: container)
        let deck = try model.saveDeck(title: "Mazo de prueba · Repaso general", notebookID: nil)
        let date = Date.now
        let first = try model.saveCard(deckID: deck.id, question: "¿Cuál es la derivada de x²?", answer: "2x.", source: nil, now: date)
        let second = try model.saveCard(deckID: deck.id, question: "¿En qué año comenzó la Revolución francesa?", answer: "1789.", source: nil, now: date.addingTimeInterval(1))
        try model.review(first.id, rating: .good, at: date); try model.review(second.id, rating: .easy, at: date)
        XCTAssertTrue(model.due(at: date, deckID: deck.id).isEmpty)
        let dates = [first.nextReviewAt, second.nextReviewAt]
        let records = try model.context.fetchCount(FetchDescriptor<ReviewRecord>())
        try await capture(AnyView(NavigationStack { StudyDeckView(model: model, deck: deck) { _ in } }), name: "Deck-Practice-All-With-No-Due-Cards")
        let practice = StudyReviewSession(cards: model.cards(in: deck), mode: .practice)
        XCTAssertEqual(practice.cardIDs, [first.id, second.id])
        try await capture(AnyView(StudyReviewView(model: model, session: practice) { _ in }), name: "Practice-All-Question")
        practice.reveal()
        try await capture(AnyView(StudyReviewView(model: model, session: practice) { _ in }), name: "Practice-All-Answer")
        try practice.advancePractice(model: model)
        practice.reveal(); try practice.advancePractice(model: model)
        XCTAssertTrue(practice.isComplete)
        try await capture(AnyView(StudyReviewView(model: model, session: practice) { _ in }), name: "Practice-All-Repeat")
        XCTAssertTrue(practice.repeatPractice(in: model))
        XCTAssertEqual(practice.current(in: model)?.id, first.id); XCTAssertFalse(practice.isAnswerVisible)
        XCTAssertEqual([first.nextReviewAt, second.nextReviewAt], dates)
        XCTAssertEqual(try model.context.fetchCount(FetchDescriptor<ReviewRecord>()), records)
        XCTAssertTrue(model.due(at: date, deckID: deck.id).isEmpty)
        withExtendedLifetime(container) {}
    }
    func testV5UpgradeRetainsNotebookStructureAndBinaryFilesAndAddsEmptyStudy() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), bookID = UUID(), pageID = UUID(), sectionID = UUID()
        let drawing = ink(), bytes = drawing.dataRepresentation(), source = Data("original document".utf8)
        try bytes.write(to: root.appendingPathComponent("kept.drawing"))
        try source.write(to: root.appendingPathComponent("source.pdf"))
        do {
            let schema = Schema(versionedSchema: NotesSchemaV5.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let folder = NotesSchemaV5.Folder(title: "Semester"); folder.colorRawValue = "blue"
            let book = NotesSchemaV5.Notebook(title: "Biology", folder: folder, id: bookID)
            let section = NotesSchemaV5.NotebookSection(title: "Cells", sortIndex: 0, id: sectionID)
            let page = NotesSchemaV5.NotePage(pageIndex: 0, id: pageID)
            page.drawingFilePath = "kept.drawing"; page.pdfFilePath = "source.pdf"; page.pdfPageIndex = 3
            page.bookmarkTitle = "Mitosis"; page.pdfRightMargin = 200
            old.mainContext.insert(folder); old.mainContext.insert(book); old.mainContext.insert(page); old.mainContext.insert(section)
            book.pages = [page]; book.sections = [section]; page.section = section
            try old.mainContext.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url)
        let book = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Notebook>()).first)
        let page = try XCTUnwrap(book.pages.first)
        XCTAssertEqual(book.id, bookID); XCTAssertEqual(book.folder?.color, .blue)
        XCTAssertEqual(page.id, pageID); XCTAssertEqual(page.section?.id, sectionID)
        XCTAssertEqual(page.bookmarkTitle, "Mitosis"); XCTAssertEqual(page.pdfPageIndex, 3)
        XCTAssertEqual(page.drawingFilePath, "kept.drawing"); XCTAssertEqual(page.pdfRightMargin, 200)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("kept.drawing")), bytes)
        XCTAssertEqual(try PKDrawing(data: bytes), drawing)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("source.pdf")), source)
        let model = StudyViewModel(container: migrated)
        XCTAssertNil(model.loadError); XCTAssertTrue(model.decks.isEmpty && model.cards.isEmpty)
        let deck = try model.saveDeck(title: "Cells", notebookID: book.id)
        let card = try model.saveCard(deckID: deck.id, question: "Division?", answer: "Mitosis",
                                     source: .init(notebookID: bookID, pageID: pageID))
        try model.review(card.id, rating: .good, at: .now)
        XCTAssertEqual(card.reviews.count, 1)
        withExtendedLifetime(migrated) {}
    }

    func testSourceNavigationTargetsPermanentPageAndFlushesOutgoingNativeInk() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let book = Notebook(title: "Source"), outgoing = Notebook(title: "Writing")
        let a = NotePage(pageIndex: 0), b = NotePage(pageIndex: 1), c = NotePage(pageIndex: 0)
        for value in [book, outgoing] { context.insert(value) }
        for value in [a, b, c] { context.insert(value) }
        book.pages = [a, b]; outgoing.pages = [c]; try context.save()
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "StudySource.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root), workspace = DocumentWorkspace(context: context, storage: storage, defaults: defaults)
        await workspace.restore()
        let opened = await workspace.open(outgoing); XCTAssertTrue(opened)
        let session = try XCTUnwrap(workspace.activeSession)
        let canvas = InkCanvas(); canvas.pageID = c.id; canvas.drawing = ink(); session.canvas = canvas
        b.pageIndex = 0; a.pageIndex = 1; try context.save()
        let targeted = await workspace.open(book, pageID: b.id)
        XCTAssertTrue(targeted); XCTAssertEqual(workspace.activeSession?.page?.id, b.id)
        let bytes = try await storage.read(try XCTUnwrap(c.drawingFilePath))
        XCTAssertEqual(try PKDrawing(data: bytes).strokes.count, 1)
        let changedPage = await workspace.open(book, pageID: a.id)
        XCTAssertTrue(changedPage); XCTAssertEqual(workspace.activeSession?.page?.id, a.id)
        let missing = await workspace.open(book, pageID: UUID())
        XCTAssertFalse(missing); XCTAssertEqual(workspace.activeSession?.page?.id, a.id)
        book.trashedAt = .now; try context.save()
        let trashed = await workspace.open(book, pageID: b.id); XCTAssertFalse(trashed)
        workspace.activeSession?.discardPreparedPages()
        withExtendedLifetime(container) {}
    }

    func testNativeStudyDashboardDeckAndReviewProgressUseStoredData() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let model = StudyViewModel(container: container)
        let deck = try model.saveDeck(title: "Cell Biology", notebookID: nil)
        let date = Date.now
        let first = try model.saveCard(deckID: deck.id, question: "What does the mitochondrion do?",
                                      answer: "It produces most of the ATP used by the cell through cellular respiration.", source: nil, now: date.addingTimeInterval(-2))
        let second = try model.saveCard(deckID: deck.id, question: "What is the role of the nucleus?",
                                       answer: "It stores DNA and regulates gene expression.", source: nil, now: date.addingTimeInterval(-1))
        try await capture(AnyView(NavigationStack { StudyView(context: container.mainContext) { _ in } }), name: "Study-Dashboard")
        try await capture(AnyView(NavigationStack { StudyDeckView(model: model, deck: deck) { _ in } }), name: "Study-Deck")
        let session = StudyReviewSession(cards: model.due(at: date))
        XCTAssertEqual(session.cardIDs, [first.id, second.id])
        try await capture(AnyView(StudyReviewView(model: model, session: session) { _ in }), name: "Study-Question")
        session.flip()
        try await capture(AnyView(StudyReviewView(model: model, session: session) { _ in }), name: "Study-Answer")
        try session.rate(.good, model: model, now: date)
        XCTAssertEqual(session.current(in: model)?.id, second.id); XCTAssertFalse(session.isAnswerVisible)
        XCTAssertEqual(model.due(at: date).map(\.id), [second.id])
        session.reveal(); try session.rate(.again, model: model, now: date)
        XCTAssertTrue(session.isComplete); XCTAssertEqual(session.reviewedCount, 2)
        XCTAssertTrue(model.due(at: date).isEmpty)
        XCTAssertEqual(try model.context.fetchCount(FetchDescriptor<ReviewRecord>()), 2)
        try await capture(AnyView(StudyReviewView(model: model, session: session) { _ in }), name: "Study-Complete")
        withExtendedLifetime(container) {}
    }

    func testFormsAndLongReviewRenderInNarrowLandscapeAndAccessibleText() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true), model = StudyViewModel(container: container)
        let deck = try model.saveDeck(title: "Revision", notebookID: nil)
        let card = try model.saveCard(deckID: deck.id, question: String(repeating: "A long question to recall. ", count: 25),
                                      answer: String(repeating: "Detailed explanation. ", count: 45), source: nil)
        let session = StudyReviewSession(cards: [card]); session.reveal()
        try await capture(AnyView(StudyReviewView(model: model, session: session) { _ in }
            .environment(\.dynamicTypeSize, .accessibility3)),
                          name: "Study-Accessible-Narrow", size: CGSize(width: 540, height: 820))
        try await capture(AnyView(StudyReviewView(model: model, session: session) { _ in }.preferredColorScheme(.dark)),
                          name: "Study-Landscape-Dark", size: CGSize(width: 1180, height: 820))
        try await capture(AnyView(FlashcardForm(model: model, deck: deck, card: card)), name: "Study-Edit-Card")
        try await capture(AnyView(StudyDeckForm(model: model)), name: "Study-New-Deck")
        withExtendedLifetime(container) {}
    }

    func testSourceOpeningClearsPushedDeckRouteAndReturnsToStudy() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let book = Notebook(title: "Linked notes"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
        try container.mainContext.save()
        let model = StudyViewModel(container: container)
        let deck = try model.saveDeck(title: "Linked deck", notebookID: book.id)
        let suite = "StudyRoute.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = DocumentWorkspace(context: container.mainContext, defaults: defaults)
        await workspace.restore()
        let navigation = LibraryNavigation(); navigation.selection = .study
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(rootView: LibraryView(context: container.mainContext, workspace: workspace, navigation: navigation))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; workspace.activeSession?.discardPreparedPages() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(300))
        navigation.studyPath = [StudyRoute(deckID: deck.id)]
        try await Task.sleep(for: .milliseconds(300)); host.view.layoutIfNeeded()
        XCTAssertEqual(navigation.studyPath.count, 1)
        let opened = await workspace.open(book, pageID: page.id); XCTAssertTrue(opened)
        try await Task.sleep(for: .milliseconds(300)); host.view.layoutIfNeeded()
        XCTAssertTrue(navigation.studyPath.isEmpty)
        XCTAssertEqual(workspace.activeSession?.page?.id, page.id)
        XCTAssertEqual(navigation.selection, .study)
        let returned = await workspace.showLibrary(); XCTAssertTrue(returned)
        try await Task.sleep(for: .milliseconds(100)); host.view.layoutIfNeeded()
        XCTAssertNil(workspace.activeSession); XCTAssertTrue(navigation.studyPath.isEmpty)
        withExtendedLifetime(container) {}
    }

    private func capture(_ content: AnyView, name: String, size: CGSize = CGSize(width: 820, height: 1180)) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300)); host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.size, size)
        let image = UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func ink() -> PKDrawing {
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 90)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }
}
