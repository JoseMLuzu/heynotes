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
