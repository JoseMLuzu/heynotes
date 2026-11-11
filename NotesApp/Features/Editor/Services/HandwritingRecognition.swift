import PencilKit
import UIKit
import Vision

protocol HandwritingRecognizing: Sendable {
    func recognize(_ drawing: PKDrawing, language: String) async throws -> String?
}

/// Raster OCR is intentionally a replaceable adapter, not a calligraphy/style-transfer model.
/// All rendering and Vision work happens on this actor, never on the canvas's MainActor.
actor VisionHandwritingRecognizer: HandwritingRecognizing {
    static let shared = VisionHandwritingRecognizer()

    func recognize(_ drawing: PKDrawing, language: String) async throws -> String? {
        try Task.checkCancellation()
        guard let (image, bounds) = Self.raster(drawing), let cgImage = image.cgImage else { return nil }
        return try recognizeImage(cgImage, bounds: bounds, strokes: drawing.strokes, language: language)
    }

    nonisolated static func raster(_ drawing: PKDrawing) -> (UIImage, CGRect)? {
        // Vision's text detector can miss an otherwise legible word when the crop is
        // almost entirely glyphs. Keep contextual whitespace around short phrases.
        let padding = max(32, min(96, drawing.bounds.height * 0.75))
        let bounds = drawing.bounds.insetBy(dx: -padding, dy: -padding)
        guard !drawing.strokes.isEmpty, drawing.strokes.count <= 1_000,
              !bounds.isNull, bounds.width > 0, bounds.height > 0,
              max(bounds.width, bounds.height) <= 4_096 else { return nil }
        // Normalize light ink for OCR without altering stored color or source strokes.
        let black = PKDrawing(strokes: drawing.strokes.map { original in
            var stroke = original
            var ink = original.ink; ink.color = .black
            stroke.ink = ink
            return stroke
        })
        let scale = min(3, 2_048 / max(bounds.width, bounds.height))
        var image: UIImage?
        // PencilKit adapts black ink to white in Dark Mode, even for an offscreen image.
        // OCR always needs black ink on white paper, independent of the app appearance.
        // performAsCurrent is synchronous and supported on background threads.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
            image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: bounds.size))
                black.image(from: bounds, scale: scale).draw(in: CGRect(origin: .zero, size: bounds.size))
            }
        }
        guard let image else { return nil }
        return (image, bounds)
    }

    private func recognizeImage(_ cgImage: CGImage, bounds: CGRect, strokes: [PKStroke], language: String) throws -> String? {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        guard supported.contains(language) else { return nil }
        request.recognitionLanguages = [language]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        try Task.checkCancellation()
        let lines = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        guard !lines.isEmpty, lines.count <= 12 else { return nil }
        var strings: [String] = []
        var regions: [CGRect] = []
        for line in lines {
            guard let candidate = line.topCandidates(1).first, candidate.confidence >= 0.5 else { return nil }
            strings.append(candidate.string)
            let box = line.boundingBox
            regions.append(CGRect(x: bounds.minX + box.minX * bounds.width,
                                  y: bounds.minY + (1 - box.maxY) * bounds.height,
                                  width: box.width * bounds.width, height: box.height * bounds.height)
                .insetBy(dx: -12, dy: -12))
        }
        // Do not remove a diagram or marginal marks alongside recognized text.
        guard strokes.allSatisfy({ stroke in
            regions.contains { $0.contains(CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)) }
        }) else { return nil }
        let text = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
