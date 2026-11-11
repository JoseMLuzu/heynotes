import XCTest
@testable import NotesAppCore

final class HandwritingMetadataTests: XCTestCase {
    func testOldTextDecodesAndSourceInkRoundTripsWithoutSchemaChanges() throws {
        var item = PageElement(kind: .text, rect: CGRect(x: 20, y: 30, width: 240, height: 80))
        item.text = "Original text"
        let old = try PageElementsCodec.encode([item])
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        var items = try XCTUnwrap(envelope["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "fontName"); items[0].removeValue(forKey: "originalInk")
        envelope["items"] = items
        let decoded = try PageElementsCodec.decode(JSONSerialization.data(withJSONObject: envelope))
        XCTAssertEqual(decoded, [item]); XCTAssertNil(decoded[0].fontName); XCTAssertNil(decoded[0].originalInk)
        item.fontName = "Noteworthy-Light"; item.originalInk = Data([1, 2, 3, 4])
        XCTAssertEqual(try PageElementsCodec.decode(PageElementsCodec.encode([item])), [item])
        item.fontName = String(repeating: "x", count: 129)
        XCTAssertThrowsError(try PageElementsCodec.encode([item]))
    }
}
