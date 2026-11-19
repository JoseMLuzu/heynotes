import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor final class SmartShapeTests: XCTestCase {
    func testPauseIgnoresScreenJitterAtFitAndHighZoom() async throws {
        for zoom: CGFloat in [0.5, 4] {
            let tracker = ShapeHoldTracker(holdDelay: .milliseconds(40))
            var matches = 0, ended = false
            tracker.onMatch = { if $0?.kind == .line { matches += 1 } }
            tracker.onEnd = { ended = $0 }
            tracker.begin(at: .zero, screenPoint: .zero, screenScale: zoom)
            tracker.append([CGPoint(x: 120 / zoom, y: 0)], screenPoint: CGPoint(x: 120, y: 0))
            for i in 0..<10 {
                let jitter = CGFloat(i.isMultiple(of: 2) ? 2 : -2)
                tracker.append([CGPoint(x: (120 + jitter) / zoom, y: jitter / zoom)], screenPoint: CGPoint(x: 120 + jitter, y: jitter))
                try await Task.sleep(for: .milliseconds(15))
            }
            XCTAssertEqual(matches, 1, "Micro-movement must not continually restart the hold timer")
            tracker.end(); XCTAssertTrue(ended)
        }
    }

    func testContinuedDrawingRearmsHoldAndCancellationDoesNotSnap() async throws {
        let tracker = ShapeHoldTracker(holdDelay: .milliseconds(40))
        var matches = 0, cleared = 0, ended: Bool?
        tracker.onMatch = { if $0 != nil { matches += 1 } else { cleared += 1 } }
        tracker.onEnd = { ended = $0 }
        tracker.begin(at: .zero, screenPoint: .zero, screenScale: 1)
        tracker.append([CGPoint(x: 100, y: 0)], screenPoint: CGPoint(x: 100, y: 0))
        try await wait { matches == 1 }
        tracker.append([CGPoint(x: 160, y: 0)], screenPoint: CGPoint(x: 160, y: 0))
        XCTAssertEqual(cleared, 1)
        try await wait { matches == 2 }
        tracker.end(cancelled: true); XCTAssertEqual(ended, false)
        tracker.begin(at: .zero, screenPoint: .zero, screenScale: 1)
        tracker.append([CGPoint(x: 100, y: 0)], screenPoint: CGPoint(x: 100, y: 0))
        tracker.end()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(ended, false); XCTAssertEqual(matches, 2)
    }

    func testAllCompletionOrdersCommitExactlyOnceWithUndoAndRecoverableInk() async throws {
        for order in 0..<3 {
            let f = try ShapeFixture(); defer { f.cleanup() }; await f.open()
            try await f.hold()
            var changedStyle = f.initialStyle; changedStyle.red = 0.1
            f.coordinator.attach(to: f.canvas, session: f.session, enabled: true, style: changedStyle)
            let full = f.fullDrawing
            if order != 2 { f.canvas.drawing = full; f.session.changed(full) }
            switch order {
            case 0:
                f.coordinator.didChange(f.canvas)
                f.coordinator.observer.tracker.end()
                f.coordinator.didEnd(f.canvas) // Previously missed: change arrived before end.
            case 1:
                f.coordinator.didEnd(f.canvas)
                f.coordinator.observer.tracker.end()
                f.coordinator.didChange(f.canvas)
            default:
                f.coordinator.observer.tracker.end()
                f.coordinator.didEnd(f.canvas) // Stroke data is not committed yet.
                f.canvas.drawing = full; f.session.changed(full)
                f.coordinator.didChange(f.canvas)
            }
            for _ in 0..<3 { f.coordinator.didChange(f.canvas) }
            try await wait { f.session.elements.count == 1 }
            let shape = try XCTUnwrap(f.session.elements.first)
            XCTAssertEqual(shape.kind, .line); XCTAssertEqual(f.canvas.drawing, f.before)
            XCTAssertEqual(shape.red, f.initialStyle.red)
            XCTAssertTrue(try StrokeContent.matches(PKDrawing(data: XCTUnwrap(shape.originalInk)).strokes, [f.added]))
            f.canvas.undoManager?.undo()
            XCTAssertEqual(f.session.drawing, full); XCTAssertTrue(f.session.elements.isEmpty)
            f.canvas.undoManager?.redo()
            XCTAssertEqual(f.session.elements.first?.id, shape.id); XCTAssertEqual(f.session.drawing, f.before)
            let saved = await f.session.flush(); XCTAssertTrue(saved)
            let bytes = try await f.storage.read(try XCTUnwrap(f.page.drawingFilePath))
            XCTAssertEqual(try PKDrawing(data: bytes), f.before)
            XCTAssertTrue(f.session.restoreOriginalInk(shape.id))
            XCTAssertTrue(try StrokeContent.matches(f.canvas.drawing.strokes, full.strokes))
        }
    }

    func testBackgroundDisableAndStalePageKeepOriginalHandwriting() async throws {
        for cancellation in 0..<3 {
            let f = try ShapeFixture(); defer { f.cleanup() }; await f.open()
            try await f.hold()
            let full = f.fullDrawing; f.canvas.drawing = full; f.session.changed(full)
            if cancellation == 0 { NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil) }
            if cancellation == 1 { f.coordinator.attach(to: f.canvas, session: f.session, enabled: false, style: f.initialStyle) }
            if cancellation == 2 { f.canvas.pageID = UUID() }
            f.coordinator.observer.tracker.end(); f.coordinator.didEnd(f.canvas); f.coordinator.didChange(f.canvas)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(f.session.elements.isEmpty); XCTAssertEqual(f.canvas.drawing, full)
        }
    }

    func testRepeatedAttachmentKeepsHoldAndPendingCancelKeepsInk() async throws {
        let f = try ShapeFixture(); defer { f.cleanup() }; await f.open()
        f.coordinator.observer.tracker.begin(at: CGPoint(x: 40, y: 80), screenPoint: CGPoint(x: 40, y: 80), screenScale: 1)
        f.coordinator.observer.tracker.append([CGPoint(x: 140, y: 81)], screenPoint: CGPoint(x: 140, y: 81))
        var newerStyle = f.initialStyle; newerStyle.red = 0.1
        f.coordinator.attach(to: f.canvas, session: f.session, enabled: true, style: newerStyle)
        try await wait { f.matched }
        let full = f.fullDrawing; f.canvas.drawing = full; f.session.changed(full)
        f.coordinator.observer.tracker.end(); f.coordinator.didEnd(f.canvas)
        f.coordinator.cancel() // New stroke/tool/page wins before asynchronous replacement.
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(f.session.elements.isEmpty); XCTAssertEqual(f.canvas.drawing, full)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Shape state did not settle")
    }
}

@MainActor private final class ShapeFixture {
    private static var containers: [ModelContainer] = []
    let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let storage: DrawingStorage
    let container: ModelContainer
    let page = NotePage(pageIndex: 0)
    let canvas = InkCanvas()
    let coordinator = SmartShapeCoordinator()
    let session: EditorSession
    var matched = false
    var initialStyle: InkStyle { var value = InkStyle(); value.red = 0.8; value.green = 0.2; value.blue = 0.1; return value }
    let added: PKStroke
    let before: PKDrawing
    var fullDrawing: PKDrawing { PKDrawing(strokes: before.strokes + [added]) }
    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true); Self.containers.append(container)
        storage = DrawingStorage(root: root)
        let book = Notebook(title: "Held shapes")
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]
        try container.mainContext.save()
        session = EditorSession(notebook: book, context: container.mainContext, storage: storage)
        added = Self.stroke(y: 80); before = PKDrawing(strokes: [Self.stroke(y: 300)])
    }
    func open() async {
        await session.open(page); canvas.pageID = page.id; session.canvas = canvas
        canvas.drawing = before; session.changed(before); canvas.undoManager?.removeAllActions()
        coordinator.attach(to: canvas, session: session, enabled: true, style: initialStyle)
        let originalMatch = coordinator.observer.onMatch
        coordinator.observer.onMatch = { [weak self] value in originalMatch?(value); self?.matched = value != nil }
    }
    func hold() async throws {
        let tracker = coordinator.observer.tracker
        tracker.begin(at: CGPoint(x: 40, y: 80), screenPoint: CGPoint(x: 40, y: 80), screenScale: 1)
        tracker.append([CGPoint(x: 140, y: 81)], screenPoint: CGPoint(x: 140, y: 81))
        for _ in 0..<100 {
            if matched { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected a held line preview")
    }
    func cleanup() { coordinator.detach(); session.handwriting.cancel(); session.discardPreparedPages(); try? FileManager.default.removeItem(at: root) }
    private static func stroke(y: CGFloat) -> PKStroke {
        let points = (0...10).map { i in PKStrokePoint(location: CGPoint(x: 40 + CGFloat(i) * 10, y: y), timeOffset: Double(i) * 0.01,
            size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2) }
        return PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }
}
