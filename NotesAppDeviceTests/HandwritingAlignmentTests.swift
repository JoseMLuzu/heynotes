import XCTest
import PencilKit
import CoreText
import UIKit
@testable import NotesApp

@MainActor final class HandwritingAlignmentTests: XCTestCase {
    private let size = CGSize(width: 768, height: 1086)
    private func ink(y: CGFloat = 125) -> PKDrawing {
        let points = [CGPoint(x: 70, y: y - 17), CGPoint(x: 110, y: y)]
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.05, size: CGSize(width: 2, height: 2),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSince1970: 1)))
        return PKDrawing(strokes: [stroke])
    }
    private func baseline(_ item: PageElement) -> CGFloat {
        let frame = PageElementRenderer.textFrame(for: item)
        var origin = CGPoint.zero
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 1), &origin)
        return item.y + item.height - origin.y
    }
    private func converted(_ text: String, drawing: PKDrawing, font: String, template: PaperTemplate? = .ruled,
                           options: HandwritingLayoutOptions = .init()) throws -> PageElement {
        try XCTUnwrap(HandwritingTextLayout.make(lines: [.init(text: text, bounds: drawing.bounds)], source: drawing,
            pageSize: size, template: template, fontName: font, fontPath: nil, options: options)?.first?.item)
    }

    func testDifferentFontsAndDescendersUseTheSameRuledBaseline() throws {
        var previews: [PageElement] = []
        for (index, font) in HandwritingFont.choices.enumerated() {
            for text in ["HELLO", "gyp", "café"] {
                let item = try converted(text, drawing: ink(), font: font.name)
                XCTAssertEqual(baseline(item), 128, accuracy: 0.01, "\(font.name): \(text)")
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(item.rect))
            }
            let y = CGFloat(93 + index * 64)
            previews.append(try converted("Hello gyp", drawing: ink(y: y), font: font.name))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            TemplateRenderer.draw(.ruled, size: size, in: ctx.cgContext)
            PageElementRenderer.draw(previews, images: [:], in: ctx.cgContext)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Font-baselines-on-actual-ruled-paper"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSeparatedLinesKeepTheirSpacingAndIndependentOriginalStrokes() throws {
        let first = ink(), second = ink(y: 189)
        let source = PKDrawing(strokes: first.strokes + second.strokes)
        let result = try XCTUnwrap(HandwritingTextLayout.make(lines: [
            .init(text: "First", bounds: first.bounds), .init(text: "Second", bounds: second.bounds)
        ], source: source, pageSize: size, template: .ruled, fontName: HandwritingFont.defaultName, fontPath: nil, options: .init()))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(baseline(result[0].item), 128, accuracy: 0.01)
        XCTAssertEqual(baseline(result[1].item), 192, accuracy: 0.01)
        XCTAssertEqual(result[0].ink.strokes.map(\.renderBounds), first.strokes.map(\.renderBounds))
        XCTAssertEqual(result[1].ink.strokes.map(\.renderBounds), second.strokes.map(\.renderBounds))
    }

    func testBlankPDFAndDisabledAlignmentKeepInkPositionAndCalibrationMovesOnlyTheBaseline() throws {
        let drawing = ink(y: 136), font = HandwritingFont.defaultName
        let blank = try converted("Hello", drawing: drawing, font: font, template: .blank)
        let pdf = try converted("Hello", drawing: drawing, font: font, template: nil)
        let disabled = try converted("Hello", drawing: drawing, font: font, options: .init(alignToPaper: false))
        XCTAssertEqual(blank.rect, pdf.rect); XCTAssertEqual(blank.rect, disabled.rect)
        let plain = try converted("gyp", drawing: ink(), font: font)
        let adjusted = try converted("gyp", drawing: ink(), font: font, options: .init(baselineOffset: -4))
        XCTAssertEqual(baseline(adjusted), baseline(plain) - 4, accuracy: 0.01)
        XCTAssertEqual(adjusted.fontSize, plain.fontSize)
        let larger = try converted("Hello", drawing: drawing, font: font, template: .blank, options: .init(sizeScale: 1.3))
        XCTAssertGreaterThan(larger.fontSize, blank.fontSize)
        XCTAssertEqual(HandwritingTextLayout.writingGuide(near: CGPoint(x: 400, y: 190), template: .cornell, size: size)?.y, 190)
        XCTAssertNil(HandwritingTextLayout.writingGuide(near: CGPoint(x: 70, y: 80), template: .lecture, size: size))
        XCTAssertNil(HandwritingTextLayout.writingGuide(near: CGPoint(x: 100, y: 190), template: .cornell, size: size))
    }
}
