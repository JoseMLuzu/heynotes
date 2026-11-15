import PencilKit

enum SelectiveInkEraser {
    /// The selective mode erases complete marker strokes only; other strokes are retained intact.
    static func eraseHighlighter(_ drawing: PKDrawing, along points: [CGPoint], radius: CGFloat) -> PKDrawing {
        guard !points.isEmpty, radius.isFinite, radius > 0 else { return drawing }
        let path = points.prefix(4096)
        let sweep = path.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -radius - 30, dy: -radius - 30)
        let kept = drawing.strokes.filter { stroke in
            guard stroke.ink.inkType == .marker, stroke.renderBounds.intersects(sweep) else { return true }
            let ranges = stroke.maskedPathRanges
            for range in ranges {
                for sample in stroke.path.interpolatedPoints(in: range, by: .distance(max(2, min(8, radius / 2)))) {
                    let point = sample.location.applying(stroke.transform)
                    let scale = max(hypot(stroke.transform.a, stroke.transform.b), hypot(stroke.transform.c, stroke.transform.d))
                    let effective = radius + max(sample.size.width, sample.size.height) * scale / 2
                    if path.count == 1, hypot(point.x - points[0].x, point.y - points[0].y) <= effective { return false }
                    for (a, b) in zip(path, path.dropFirst()) where StudentToolGeometry.distance(point, to: a, b) <= effective { return false }
                }
            }
            return true
        }
        return kept.count == drawing.strokes.count ? drawing : PKDrawing(strokes: kept)
    }
}
