import XCTest
import UIKit
@testable import NotesApp

@MainActor final class LaserPointerTests: XCTestCase {
    func testReleasedStrokeKeepsItsPathAndWaitsThreeSecondsBeforeFading() throws {
        let laser = LaserPointerVisual()
        defer { laser.clear() }
        laser.show([CGPoint(x: 20, y: 30), CGPoint(x: 90, y: 80)])
        let stroke = try XCTUnwrap(laser.layer.sublayers?.first)
        let path = try XCTUnwrap((stroke.sublayers?.first as? CAShapeLayer)?.path)
        XCTAssertNil(stroke.animation(forKey: "fade"))
        let releasedAt = stroke.convertTime(CACurrentMediaTime(), from: nil)
        laser.finishStroke()
        let fade = try XCTUnwrap(stroke.animation(forKey: "fade") as? CABasicAnimation)
        XCTAssertEqual(stroke.opacity, 1)
        XCTAssertEqual((stroke.sublayers?.first as? CAShapeLayer)?.path, path)
        XCTAssertGreaterThanOrEqual(fade.beginTime - releasedAt, 3)
        XCTAssertLessThan(fade.beginTime - releasedAt, 3.1)
        XCTAssertEqual(fade.duration, 0.6)

        // A new letter and a color change cannot replace/recolor the released letter.
        let oldColor = (stroke.sublayers?.first as? CAShapeLayer)?.strokeColor
        laser.style = InkStyle(red: 0, green: 0.3, blue: 1, width: 4)
        laser.show([CGPoint(x: 120, y: 30), CGPoint(x: 180, y: 90)])
        XCTAssertEqual(laser.layer.sublayers?.count, 2)
        XCTAssertEqual((stroke.sublayers?.first as? CAShapeLayer)?.path, path)
        XCTAssertEqual((stroke.sublayers?.first as? CAShapeLayer)?.strokeColor, oldColor)
        XCTAssertNotNil(stroke.animation(forKey: "fade"))
        XCTAssertNil(laser.layer.sublayers?.last?.animation(forKey: "fade"))
    }

    func testExpiryOnlyRemovesReleasedStrokeAndClearCancelsOldDeadlines() async throws {
        let laser = LaserPointerVisual(holdDuration: 0.05, fadeDuration: 0.05)
        laser.show([CGPoint(x: 20, y: 30)]) // A tap also stays visible.
        laser.finishStroke()
        let released = try XCTUnwrap(laser.layer.sublayers?.first)
        laser.show([CGPoint(x: 80, y: 100), CGPoint(x: 140, y: 100)])
        let active = try XCTUnwrap(laser.layer.sublayers?.last)
        XCTAssertEqual(laser.layer.sublayers?.count, 2)
        try await waitUntil { released.superlayer == nil }
        XCTAssertTrue(active.superlayer === laser.layer)
        XCTAssertEqual(laser.layer.sublayers?.count, 1)
        laser.finishStroke()
        laser.clear()
        XCTAssertTrue(laser.layer.sublayers?.isEmpty ?? true)
        laser.show([CGPoint(x: 200, y: 200)])
        let fresh = try XCTUnwrap(laser.layer.sublayers?.first)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(fresh.superlayer === laser.layer, "An old deadline must never clear new handwriting")
        laser.clear()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Released laser stroke did not expire")
    }
}
