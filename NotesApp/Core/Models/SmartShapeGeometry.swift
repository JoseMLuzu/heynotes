import Foundation
import CoreGraphics

/// Spatial sampling gives a slow corner and a fast edge equal weight. All tolerances
/// are relative to shape size; minimumSize is supplied in logical page coordinates.
public enum SmartShapeGeometry {
    public static func match(_ input: [CGPoint], minimumSize: CGFloat = 24) -> SmartShapeMatch? {
        guard input.count >= 2, input.count <= 4096, minimumSize.isFinite, minimumSize > 0,
              input.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let points = resample(input, count: 96)
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        let rect = bounds(points), diagonal = hypot(rect.width, rect.height)
        guard diagonal >= minimumSize else { return nil }
        if let line = line(points, minimumSize: minimumSize) { return line }
        let precision = minimumSize / 24
        guard points.count >= 8, min(rect.width, rect.height) >= minimumSize * 0.45,
              distance(first, last) <= max(4 * precision, diagonal * 0.20) else { return nil }
        if isRectangle(points, rect: rect, precision: precision) {
            return SmartShapeMatch(kind: .rectangle, rect: rect, reversed: false)
        }
        if isEllipse(points, rect: rect) {
            return SmartShapeMatch(kind: .ellipse, rect: rect, reversed: false)
        }
        return nil
    }

    private static func line(_ points: [CGPoint], minimumSize: CGFloat) -> SmartShapeMatch? {
        let n = CGFloat(points.count)
        let center = CGPoint(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for p in points {
            let x = p.x - center.x, y = p.y - center.y
            xx += x * x; yy += y * y; xy += x * y
        }
        let angle = atan2(2 * xy, xx - yy) / 2, dx = cos(angle), dy = sin(angle)
        let projections = points.map { ($0.x - center.x) * dx + ($0.y - center.y) * dy }
        let low = projections.min()!, high = projections.max()!, span = high - low
        let errors = points.map { abs(($0.x - center.x) * dy - ($0.y - center.y) * dx) }.sorted()
        let precision = minimumSize / 24
        guard span >= minimumSize, length(points) <= span * 1.25,
              distance(points.first!, points.last!) >= span * 0.72,
              errors.reduce(0, +) / n <= max(0.8 * precision, span * 0.04),
              errors[Int(CGFloat(errors.count - 1) * 0.9)] <= max(1.2 * precision, span * 0.075) else { return nil }
        var start = CGPoint(x: center.x + low * dx, y: center.y + low * dy)
        var end = CGPoint(x: center.x + high * dx, y: center.y + high * dy)
        // Small near-horizontal/vertical hand wobble should become a level edge.
        if abs(dy) < sin(.pi / 36) { start.y = center.y; end.y = center.y }
        if abs(dx) < sin(.pi / 36) { start.x = center.x; end.x = center.x }
        var rect = bounds([start, end])
        if rect.width < 1 { rect.origin.x -= (1 - rect.width) / 2; rect.size.width = 1 }
        if rect.height < 1 { rect.origin.y -= (1 - rect.height) / 2; rect.size.height = 1 }
        return SmartShapeMatch(kind: .line, rect: rect, reversed: (end.x - start.x) * (end.y - start.y) < 0)
    }

    private static func isRectangle(_ points: [CGPoint], rect: CGRect, precision: CGFloat) -> Bool {
        let side = min(rect.width, rect.height), perimeter = 2 * (rect.width + rect.height), travel = length(points)
        guard travel >= perimeter * 0.75, travel <= perimeter * 1.35 else { return false }
        let cornerTolerance = max(2 * precision, side * 0.22)
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        guard corners.allSatisfy({ corner in points.contains { distance($0, corner) <= cornerTolerance } }) else { return false }
        let errors = points.map { min(abs($0.x - rect.minX), abs($0.x - rect.maxX), abs($0.y - rect.minY), abs($0.y - rect.maxY)) }.sorted()
        return errors.reduce(0, +) / CGFloat(errors.count) <= side * 0.10 && errors[Int(CGFloat(errors.count - 1) * 0.9)] <= side * 0.22
    }

    private static func isEllipse(_ points: [CGPoint], rect: CGRect) -> Bool {
        guard max(rect.width, rect.height) / min(rect.width, rect.height) <= 10 else { return false }
        let normalized = points.map { CGPoint(x: ($0.x - rect.midX) / (rect.width / 2), y: ($0.y - rect.midY) / (rect.height / 2)) }
        let errors = normalized.map { abs(hypot($0.x, $0.y) - 1) }.sorted()
        guard errors.reduce(0, +) / CGFloat(errors.count) <= 0.16, errors[Int(CGFloat(errors.count - 1) * 0.9)] <= 0.30 else { return false }
        var rotation: CGFloat = 0, travel: CGFloat = 0
        for (a, b) in zip(normalized, normalized.dropFirst()) {
            let delta = atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
            rotation += delta; travel += abs(delta)
        }
        return abs(rotation) >= 5.2 && abs(rotation) <= 7.0 && travel <= 8.5 && abs(rotation) >= travel * 0.75
    }

    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        var clean = [points[0]], cumulative: [CGFloat] = [0]
        for p in points.dropFirst() {
            let segment = distance(clean.last!, p)
            if segment > 0.00001 { clean.append(p); cumulative.append(cumulative.last! + segment) }
        }
        guard clean.count > 1, let total = cumulative.last, total > 0 else { return clean }
        var result = [clean[0]], index = 1
        for sample in 1..<(count - 1) {
            let target = total * CGFloat(sample) / CGFloat(count - 1)
            while index < cumulative.count - 1 && cumulative[index] < target { index += 1 }
            let a = clean[index - 1], b = clean[index]
            let t = (target - cumulative[index - 1]) / (cumulative[index] - cumulative[index - 1])
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        result.append(clean.last!); return result
    }
    private static func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func length(_ points: [CGPoint]) -> CGFloat { zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) } }
}
