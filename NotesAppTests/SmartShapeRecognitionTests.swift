import Foundation
import Testing
@testable import NotesAppCore

struct SmartShapeRecognitionTests {
    @Test func unevenSpeedJitterAndNearlyClosedEllipsesAreRecognized() {
        var points = (0...200).map { i -> CGPoint in
            let a = pow(Double(i) / 200, 1.8) * .pi * 1.975
            return CGPoint(x: 120 + cos(a) * 70 + sin(a * 13) * 2.5, y: 100 + sin(a) * 40 + cos(a * 11) * 2)
        }
        points.insert(contentsOf: Array(repeating: points[0], count: 900), at: 1)
        #expect(SmartShapeGeometry.match(points)?.kind == .ellipse)
    }
    @Test func roughRectangleDoesNotDependOnCornerDwellOrEdgeSampleDensity() {
        let corners = [CGPoint(x: 0, y: 2), CGPoint(x: 99, y: -1), CGPoint(x: 102, y: 69), CGPoint(x: -2, y: 71), CGPoint(x: 1, y: 6)]
        var points: [CGPoint] = []
        for edge in 0..<4 {
            let count = edge == 0 ? 900 : 12
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count)
                points.append(CGPoint(x: corners[edge].x + t * (corners[edge + 1].x - corners[edge].x) + sin(t * .pi * 8) * 1.2,
                                      y: corners[edge].y + t * (corners[edge + 1].y - corners[edge].y) + sin(t * .pi * 6) * 1.2))
            }
        }
        points.append(corners.last!)
        #expect(SmartShapeGeometry.match(points)?.kind == .rectangle)
    }
    @Test func SmallShapesUseTheVisibleZoomThresholdAndKeepPageCoordinates() throws {
        let shape = [CGPoint(x: 10, y: 20), CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 27), CGPoint(x: 10, y: 27), CGPoint(x: 10, y: 20)]
        #expect(SmartShapeGeometry.match(shape) == nil)
        let match = try #require(SmartShapeGeometry.match(shape, minimumSize: 6))
        #expect(match.kind == .rectangle)
        #expect(abs(match.rect.minX - 10) < 0.1 && abs(match.rect.maxY - 27) < 0.1)
        for zoom in [0.5, 1.0, 4.0] {
            let resized = shape.map { CGPoint(x: $0.x / zoom, y: $0.y / zoom) }
            #expect(SmartShapeGeometry.match(resized, minimumSize: 6 / zoom)?.kind == .rectangle)
        }
    }
    @Test func SparseAndWobblyLinesFitTheirDirectionAndLevelEdges() throws {
        #expect(SmartShapeGeometry.match([CGPoint(x: 10, y: 80), CGPoint(x: 100, y: 20)])?.reversed == true)
        let points = (0...60).map { CGPoint(x: 40 + Double($0) * 2, y: 80 + sin(Double($0) * 0.7) * 1.5) }
        let match = try #require(SmartShapeGeometry.match(points))
        #expect(match.kind == .line && match.rect.height == 1)
        #expect(abs(match.rect.midY - 80) < 0.5)
        #expect(SmartShapeGeometry.match([.zero, CGPoint(x: 3, y: 2)]) == nil)
    }
    @Test func OpenCurvesScribblesDoubleLoopsAndUnsupportedPolygonsRemainInk() {
        let open = (0...60).map { i in let a = Double(i) / 60 * .pi * 1.5; return CGPoint(x: 100 + cos(a) * 60, y: 100 + sin(a) * 40) }
        let twice = (0...160).map { i in let a = Double(i) / 160 * .pi * 4; return CGPoint(x: 100 + cos(a) * 60, y: 100 + sin(a) * 40) }
        let triangle = [CGPoint(x: 0, y: 80), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 0, y: 80)]
        let zigzag = (0...20).map { CGPoint(x: Double($0) * 5, y: $0.isMultiple(of: 2) ? 0 : 40) }
        for shape in [open, twice, triangle, zigzag, Array(repeating: CGPoint.zero, count: 50)] {
            #expect(SmartShapeGeometry.match(shape) == nil)
        }
        #expect(SmartShapeGeometry.match([.zero, CGPoint(x: CGFloat.infinity, y: 40)]) == nil)
        #expect(SmartShapeGeometry.match([.zero, CGPoint(x: 100, y: 40)], minimumSize: .nan) == nil)
    }
}
