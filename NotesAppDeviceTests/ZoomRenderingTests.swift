import XCTest
import UIKit
@testable import NotesApp

@MainActor final class ZoomRenderingTests: XCTestCase {
    func testTiledSmallTextMatchesHighResolutionRenderingAndUpdatesItsCache() throws {
        let content = PageObjectsContentView(frame: CGRect(x: 0, y: 0, width: 14400, height: 14400))
        let tiles = try XCTUnwrap(content.layer as? PageObjectsTileLayer)
        var text = PageElement(kind: .text, rect: CGRect(x: 900, y: 1200, width: 160, height: 30))
        text.text = "Small handwriting"; text.fontSize = 12; text.fontName = HandwritingFont.defaultName
        let patch = CGRect(x: 895, y: 1195, width: 175, height: 45)
        for message in ["Small handwriting", "Updated handwriting"] {
            text.text = message; content.elements = [text]
            let high = render(patch, scale: 8) { PageElementRenderer.draw([text], images: [:], in: $0) }
            let tiled = render(patch, scale: 8) { tiles.draw(in: $0) }
            XCTAssertEqual(tiled.pngData(), high.pngData())
            let low = render(patch, scale: 1) { PageElementRenderer.draw([text], images: [:], in: $0) }
            let enlarged = render(CGRect(origin: .zero, size: patch.size), scale: 8) { _ in low.draw(in: CGRect(origin: .zero, size: patch.size)) }
            XCTAssertNotEqual(tiled.pngData(), enlarged.pngData(), "Tiles must rerender glyph edges rather than enlarge a page bitmap")
        }
    }

    private func render(_ patch: CGRect, scale: CGFloat, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: patch.size, format: format).image {
            UIColor.white.setFill(); $0.fill(CGRect(origin: .zero, size: patch.size))
            $0.cgContext.translateBy(x: -patch.minX, y: -patch.minY); draw($0.cgContext)
        }
    }
}
