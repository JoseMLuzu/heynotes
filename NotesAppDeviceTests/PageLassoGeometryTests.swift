import XCTest
import PencilKit
@testable import NotesApp

@MainActor final class PageLassoGeometryTests: XCTestCase {
    private func box(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    private func stroke(_ points: [CGPoint], width: CGFloat = 3, marker: Bool = false,
                        transform: CGAffineTransform = .identity, mask: UIBezierPath? = nil) -> PKStroke {
        PKStroke(ink: PKInk(marker ? .marker : .pen, color: marker ? .yellow : .blue), path: PKStrokePath(controlPoints: points.enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1, size: CGSize(width: width, height: width),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSince1970: 1)), transform: transform, mask: mask)
    }
    func testMixedContentAndTransformedInkAreSelectedWithoutChangingTheirIDs() throws {
        let inside = stroke([CGPoint(x: 30, y: 30), CGPoint(x: 90, y: 90)])
        let transformed = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)], transform: CGAffineTransform(translationX: 150, y: 100))
        let outside = stroke([CGPoint(x: 600, y: 500), CGPoint(x: 650, y: 500)])
        var objects = [PageElementKind.text, .image, .rectangle, .ellipse, .arrow, .tape].enumerated().map { index, kind in
            PageElement(kind: kind, rect: CGRect(x: 40 + index * 60, y: 200, width: 40, height: 40))
        }
        objects[0].text = "Converted handwriting"; objects[1].imagePath = "image.jpg"
        var sticky = PageElement(kind: .text, rect: CGRect(x: 100, y: 300, width: 120, height: 100)); sticky.stickyStyle = .rose
        let untouched = PageElement(kind: .text, rect: CGRect(x: 600, y: 100, width: 100, height: 40))
        objects += [sticky, untouched]
        let drawing = PKDrawing(strokes: [inside, transformed, outside])
        let selected = try XCTUnwrap(PageLassoSelection.select(points: box(CGRect(x: 10, y: 10, width: 420, height: 440)),
            drawing: drawing, elements: objects, tolerance: 3))
        XCTAssertEqual(selected.strokeIndices, [0, 1]); XCTAssertEqual(selected.elementIDs, Set(objects.dropLast().map(\.id)))
        let moved = selected.moving(by: CGPoint(x: 24, y: 32))
        XCTAssertEqual(moved.elements.map(\.id), objects.map(\.id))
        for original in objects {
            let item = try XCTUnwrap(moved.elements.first { $0.id == original.id })
            XCTAssertEqual(item.x - original.x, original.id == untouched.id ? 0 : 24)
            XCTAssertEqual(item.y - original.y, original.id == untouched.id ? 0 : 32)
        }
        let expected = inside.transform.concatenating(CGAffineTransform(translationX: 24, y: 32))
        XCTAssertEqual(moved.drawing.strokes[0].transform, expected)
        XCTAssertEqual(moved.drawing.strokes[2].transform, outside.transform)
        XCTAssertEqual(moved.drawing.strokes[2].path.map(\.location), outside.path.map(\.location))
        let deleted = selected.deleting()
        XCTAssertEqual(deleted.drawing.strokes.count, 1); XCTAssertEqual(deleted.elements, [untouched])
    }
    func testMarkerEdgesAndCrossingStrokesCountButMaskedOutInkDoesNot() throws {
        let marker = stroke([CGPoint(x: 106, y: 30), CGPoint(x: 106, y: 80)], width: 20, marker: true)
        let crossing = stroke([CGPoint(x: -20, y: 50), CGPoint(x: 150, y: 50)])
        let masked = stroke([CGPoint(x: 20, y: 150), CGPoint(x: 20, y: 20)],
            mask: UIBezierPath(rect: CGRect(x: 0, y: 120, width: 50, height: 60)))
        let distant = stroke([CGPoint(x: 140, y: 20), CGPoint(x: 140, y: 90)])
        let selection = try XCTUnwrap(PageLassoSelection.select(points: box(CGRect(x: 0, y: 0, width: 100, height: 100)),
            drawing: PKDrawing(strokes: [marker, crossing, masked, distant]), elements: [], tolerance: 2))
        XCTAssertEqual(selection.strokeIndices, [0, 1])
    }
    func testConcaveLoopAndFoldedNotesDoNotUseInvisibleBoundingContent() throws {
        let text = PageElement(kind: .text, rect: CGRect(x: 15, y: 100, width: 30, height: 30))
        let outside = PageElement(kind: .text, rect: CGRect(x: 110, y: 110, width: 40, height: 40))
        let loop = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 60),
                    CGPoint(x: 60, y: 60), CGPoint(x: 60, y: 200), CGPoint(x: 0, y: 200)]
        let chosen = try XCTUnwrap(PageLassoSelection.select(points: loop, drawing: PKDrawing(), elements: [text, outside], tolerance: 0))
        XCTAssertEqual(chosen.elementIDs, [text.id])
        var note = PageElement(kind: .text, rect: CGRect(x: 100, y: 30, width: 100, height: 200)); note.stickyStyle = .mint; note.folded = true
        let hidden = try PageLassoSelection.select(points: box(CGRect(x: 110, y: 120, width: 50, height: 40)), drawing: PKDrawing(), elements: [note], tolerance: 0)
        XCTAssertNil(hidden)
        let header = try XCTUnwrap(PageLassoSelection.select(points: box(CGRect(x: 90, y: 20, width: 130, height: 50)), drawing: PKDrawing(), elements: [note], tolerance: 0))
        XCTAssertEqual(header.bounds, note.visibleRect)
        XCTAssertEqual(header.clamped(CGPoint(x: 1000, y: 1000), pageSize: CGSize(width: 300, height: 400)), CGPoint(x: 100, y: 170))
    }
    func testOutlineInteriorsAndEmptyLoopsDoNotSelectNearbyObjects() throws {
        let rect = PageElement(kind: .rectangle, rect: CGRect(x: 0, y: 0, width: 300, height: 300))
        let ellipse = PageElement(kind: .ellipse, rect: rect.rect)
        XCTAssertNil(try PageLassoSelection.select(points: box(CGRect(x: 120, y: 120, width: 40, height: 40)),
            drawing: PKDrawing(), elements: [rect, ellipse], tolerance: 0))
        XCTAssertNil(try PageLassoSelection.select(points: [CGPoint.zero, CGPoint(x: 20, y: 0)], drawing: PKDrawing(), elements: [rect], tolerance: 2))
    }
}
