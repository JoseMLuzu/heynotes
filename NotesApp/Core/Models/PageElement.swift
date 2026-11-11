import Foundation
import CoreGraphics

public enum PageElementKind: String, Codable, CaseIterable, Sendable {
    case tape, line, rectangle, ellipse, arrow, text, image
    public var title: String { switch self { case .tape: "Study Tape"; default: rawValue.capitalized } }
}

public struct PageElement: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: PageElementKind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text = ""
    public var imagePath: String? = nil
    public var red = 0.15
    public var green = 0.35
    public var blue = 0.8
    public var opacity = 1.0
    public var lineWidth = 3.0
    public var fontSize = 24.0
    public var fontName: String? = nil
    /// Editable source strokes for handwriting conversions. Missing on older text objects.
    public var originalInk: Data? = nil
    public var reversed = false
    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public init(kind: PageElementKind, rect: CGRect) {
        self.kind = kind; x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }
}

public enum PageElementError: LocalizedError {
    case unreadable, invalid
    public var errorDescription: String? {
        switch self {
        case .unreadable: "The page's inserted content could not be read. Original data has been preserved."
        case .invalid: "An inserted object has invalid dimensions or settings."
        }
    }
}

public enum PageElementsCodec {
    private struct Envelope: Codable { var version = 1; let items: [PageElement] }
    public static func decode(_ data: Data?) throws -> [PageElement] {
        guard let data else { return [] }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1 else { throw PageElementError.unreadable }
            try validate(envelope.items); return envelope.items
        } catch { throw PageElementError.unreadable }
    }
    public static func encode(_ items: [PageElement]) throws -> Data {
        try validate(items)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Envelope(items: items))
    }
    private static func validate(_ items: [PageElement]) throws {
        var ids = Set<UUID>()
        for item in items {
            guard ids.insert(item.id).inserted,
                  [item.x, item.y, item.width, item.height, item.red, item.green, item.blue, item.opacity, item.lineWidth, item.fontSize].allSatisfy(\.isFinite),
                  item.width > 0, item.height > 0, item.width <= 14400, item.height <= 14400,
                  (0...1).contains(item.red), (0...1).contains(item.green), (0...1).contains(item.blue),
                  (0.05...1).contains(item.opacity), (0.5...60).contains(item.lineWidth), (12...96).contains(item.fontSize),
                  (item.fontName?.count ?? 0) <= 128, (item.originalInk?.count ?? 0) <= 8_388_608,
                  item.kind != .image || item.imagePath != nil else { throw PageElementError.invalid }
        }
    }
}
