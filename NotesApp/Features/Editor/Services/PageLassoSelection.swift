import PencilKit
import UIKit

/// One immutable page snapshot. Indices are valid only while the full drawing and
/// object values still match; no index is persisted or used as a document identity.
struct PageLassoSelection: Sendable {
    let drawing: PKDrawing
    let elements: [PageElement]
    let strokeIndices: Set<Int>
    let elementIDs: Set<UUID>
    let bounds: CGRect
    let movementBounds: CGRect
    var count: Int { strokeIndices.count + elementIDs.count }

    static func select(points: [CGPoint], drawing: PKDrawing, elements: [PageElement], tolerance: CGFloat) throws -> Self? {
        guard points.count >= 3, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let path = UIBezierPath(); path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }; path.close()
        guard path.bounds.width > 2, path.bounds.height > 2 else { return nil }
        let tolerance = min(12, max(0, tolerance))
        let edge = path.cgPath.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        func contains(_ point: CGPoint) -> Bool { path.contains(point) || edge.contains(point) }
        let search = path.bounds.insetBy(dx: -tolerance, dy: -tolerance)
        let edges = Array(zip(points, Array(points.dropFirst()) + [points[0]]))
        func intersects(_ a: CGPoint, _ b: CGPoint) -> Bool {
            contains(a) || contains(b) || edges.contains { segmentsCross(a, b, $0.0, $0.1) }
        }
        var indices = Set<Int>(), ids = Set<UUID>(), bounds = CGRect.null, movement = CGRect.null
        for (index, stroke) in drawing.strokes.enumerated() {
            try Task.checkCancellation()
            guard stroke.renderBounds.intersects(search) else { continue }
            var included = false
            // Inspect only visible path ranges: erased/masked ink cannot select invisible marks.
            for range in stroke.maskedPathRanges {
                var previous: CGPoint?
                for sample in stroke.path.interpolatedPoints(in: range, by: .distance(3)) {
                    let point = sample.location.applying(stroke.transform)
                    let scale = max(hypot(stroke.transform.a, stroke.transform.b), hypot(stroke.transform.c, stroke.transform.d))
                    let radius = max(sample.size.width, sample.size.height) * scale / 2 + tolerance
                    if contains(point) || previous.map({ intersects($0, point) }) == true ||
                        edges.contains(where: { StudentToolGeometry.distance(point, to: $0.0, $0.1) <= radius }) { included = true; break }
                    previous = point
                }
                if included { break }
            }
            if included { indices.insert(index); bounds = bounds.union(stroke.renderBounds); movement = movement.union(stroke.renderBounds) }
        }
        for element in elements {
            try Task.checkCancellation()
            let rect = element.visibleRect
            guard rect.intersects(search) else { continue }
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            // Rectangles cover text/images/tape/notes. Vector outlines use their actual path
            // so a loop through the empty interior of a large shape does not select it.
            let outline: [CGPoint]
            switch element.kind {
            case .line, .arrow:
                let start = CGPoint(x: rect.minX, y: element.reversed ? rect.maxY : rect.minY)
                let end = CGPoint(x: rect.maxX, y: element.reversed ? rect.minY : rect.maxY)
                if element.kind == .arrow {
                    let angle = atan2(end.y - start.y, end.x - start.x), length = max(12, element.lineWidth * 4)
                    outline = [start, end, CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)),
                               end, CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6))]
                } else { outline = [start, end] }
            case .ellipse:
                outline = (0...64).map { i in
                    let angle = CGFloat(i) / 64 * .pi * 2
                    return CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
                }
            default: outline = corners + [corners[0]]
            }
            let hit = outline.contains(where: contains) || zip(outline, outline.dropFirst()).contains { intersects($0.0, $0.1) }
            let hasArea = element.kind != .line && element.kind != .arrow &&
                (element.kind != .ellipse && element.kind != .rectangle || element.filled == true)
            let insideArea = hasArea && points.contains { point in
                if element.kind == .ellipse {
                    let x = (point.x - rect.midX) / (rect.width / 2), y = (point.y - rect.midY) / (rect.height / 2)
                    return x * x + y * y <= 1
                }
                return rect.contains(point)
            }
            if hit || insideArea {
                ids.insert(element.id); bounds = bounds.union(rect); movement = movement.union(element.rect)
            }
        }
        guard !bounds.isNull else { return nil }
        return Self(drawing: drawing, elements: elements, strokeIndices: indices, elementIDs: ids, bounds: bounds, movementBounds: movement)
    }

    func clamped(_ delta: CGPoint, pageSize: CGSize) -> CGPoint {
        func axis(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            guard value.isFinite, lower <= upper else { return 0 }; return min(upper, max(lower, value))
        }
        return CGPoint(x: axis(delta.x, min: -movementBounds.minX, max: pageSize.width - movementBounds.maxX),
                       y: axis(delta.y, min: -movementBounds.minY, max: pageSize.height - movementBounds.maxY))
    }
    func moving(by delta: CGPoint) -> (drawing: PKDrawing, elements: [PageElement]) {
        let transform = CGAffineTransform(translationX: delta.x, y: delta.y)
        let strokes = drawing.strokes.enumerated().map { index, original in
            guard strokeIndices.contains(index) else { return original }
            var stroke = original; stroke.transform = original.transform.concatenating(transform); return stroke
        }
        let objects = elements.map { original in
            guard elementIDs.contains(original.id) else { return original }
            var item = original; item.x += delta.x; item.y += delta.y; return item
        }
        return (strokeIndices.isEmpty ? drawing : PKDrawing(strokes: strokes), objects)
    }
    func deleting() -> (drawing: PKDrawing, elements: [PageElement]) {
        (strokeIndices.isEmpty ? drawing : PKDrawing(strokes: drawing.strokes.enumerated().compactMap { strokeIndices.contains($0.offset) ? nil : $0.element }),
         elements.filter { !elementIDs.contains($0.id) })
    }

    private static func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let ab = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -0.01, dy: -0.01)
        let cd = CGRect(x: min(c.x, d.x), y: min(c.y, d.y), width: abs(c.x - d.x), height: abs(c.y - d.y)).insetBy(dx: -0.01, dy: -0.01)
        return ab.intersects(cd) && cross(a, b, c) * cross(a, b, d) <= 0 && cross(c, d, a) * cross(c, d, b) <= 0
    }
}
