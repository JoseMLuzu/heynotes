import Foundation
import CoreGraphics

public enum StudentToolGeometry {
    public static func angle(vertex: CGPoint, first: CGPoint, second: CGPoint) -> Double? {
        let a = CGVector(dx: first.x - vertex.x, dy: first.y - vertex.y)
        let b = CGVector(dx: second.x - vertex.x, dy: second.y - vertex.y)
        let lengths = hypot(a.dx, a.dy) * hypot(b.dx, b.dy)
        guard lengths > 1, lengths.isFinite else { return nil }
        let cosine = Double((a.dx * b.dx + a.dy * b.dy) / lengths)
        return acos(min(1, max(-1, cosine))) * 180 / Double.pi
    }
    public static func circle(center: CGPoint, end: CGPoint, bounds: CGRect) -> CGRect? {
        guard bounds.contains(center) else { return nil }
        let radius = min(hypot(end.x - center.x, end.y - center.y),
                         center.x - bounds.minX, bounds.maxX - center.x, center.y - bounds.minY, bounds.maxY - center.y)
        guard radius >= 4, radius.isFinite else { return nil }
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
    public static func distance(_ point: CGPoint, to start: CGPoint, _ end: CGPoint) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y, squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squared))
        return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
    }
}

public struct SmartShapeMatch: Sendable {
    public let kind: PageElementKind
    public let rect: CGRect
    public let reversed: Bool
}

public enum SmartShapeGeometry {
    public static func match(_ points: [CGPoint]) -> SmartShapeMatch? {
        guard points.count >= 5, points.count <= 4096,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first, let last = points.last else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let rect = CGRect(x: xs.min()!, y: ys.min()!, width: max(1, xs.max()! - xs.min()!), height: max(1, ys.max()! - ys.min()!))
        let diagonal = hypot(rect.width, rect.height)
        guard diagonal >= 24 else { return nil }
        if hypot(last.x - first.x, last.y - first.y) > diagonal * 0.7,
           points.allSatisfy({ StudentToolGeometry.distance($0, to: first, last) < max(3, diagonal * 0.035) }) {
            return SmartShapeMatch(kind: .line, rect: rect, reversed: (last.x - first.x) * (last.y - first.y) < 0)
        }
        guard hypot(last.x - first.x, last.y - first.y) < max(10, diagonal * 0.12), min(rect.width, rect.height) >= 16 else { return nil }
        let edgeError = points.map { min(abs($0.x - rect.minX), abs($0.x - rect.maxX), abs($0.y - rect.minY), abs($0.y - rect.maxY)) }.reduce(0, +) / Double(points.count)
        if edgeError < diagonal * 0.025 { return SmartShapeMatch(kind: .rectangle, rect: rect, reversed: false) }
        let radialError = points.map { abs(hypot(($0.x - rect.midX) / (rect.width / 2), ($0.y - rect.midY) / (rect.height / 2)) - 1) }.reduce(0, +) / Double(points.count)
        if radialError < 0.12 { return SmartShapeMatch(kind: .ellipse, rect: rect, reversed: false) }
        return nil
    }
}
