import PencilKit

/// PKDrawing equality includes the drawing container's identity. Compare public stroke
/// content when checking a prefix/suffix assembled into a different drawing container.
enum StrokeContent {
    static func matches(_ lhs: [PKStroke], _ rhs: [PKStroke]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            guard a.ink.inkType == b.ink.inkType, a.ink.color.isEqual(b.ink.color),
                  a.transform == b.transform, a.randomSeed == b.randomSeed,
                  a.path.creationDate == b.path.creationDate, a.path.count == b.path.count,
                  a.mask?.cgPath == b.mask?.cgPath else { return false }
            return zip(a.path, b.path).allSatisfy { p, q in
                guard p.location == q.location, p.timeOffset == q.timeOffset,
                      p.size == q.size, p.opacity == q.opacity, p.force == q.force,
                      p.azimuth == q.azimuth, p.altitude == q.altitude,
                      p.secondaryScale == q.secondaryScale else { return false }
                if #available(iOS 26.0, *), p.threshold != q.threshold { return false }
                if #available(iOS 27.0, *), p.lateralJitter != q.lateralJitter { return false }
                return true
            }
        }
    }
}
