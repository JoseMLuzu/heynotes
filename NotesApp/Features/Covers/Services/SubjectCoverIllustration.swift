import SwiftUI

/// Quiet line illustrations in a 240 × 300 coordinate space.
enum SubjectCoverIllustration {
    static func draw(_ subject: NotebookSubject, palette: SubjectCoverPalette, context: GraphicsContext) {
        let center = CGPoint(x: 132, y: 179)
        let stroke = palette.ink.opacity(0.78)
        func line(_ points: [CGPoint], width: CGFloat = 1.4, color: Color? = nil) {
            guard let first = points.first else { return }
            var path = Path(); path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(color ?? stroke), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        func ellipse(_ rect: CGRect, fill: Color? = nil) {
            let path = Path(ellipseIn: rect)
            if let fill { context.fill(path, with: .color(fill)) }
            else { context.stroke(path, with: .color(stroke), lineWidth: 1.3) }
        }
        func box(_ rect: CGRect, radius: CGFloat = 4, fill: Color? = nil) {
            let path = Path(roundedRect: rect, cornerRadius: radius)
            if let fill { context.fill(path, with: .color(fill)) }
            context.stroke(path, with: .color(stroke), lineWidth: 1.3)
        }
        func text(_ value: String, at point: CGPoint, size: CGFloat = 15) {
            context.draw(Text(value).font(.system(size: size, weight: .regular, design: .serif)).foregroundColor(palette.ink), at: point)
        }

        // A small paper-dot field and an offset wash give the drawings a shared stationery feel.
        for x in stride(from: 38, through: 220, by: 14) {
            for y in stride(from: 116, through: 244, by: 14) {
                context.fill(Path(ellipseIn: CGRect(x: CGFloat(x), y: CGFloat(y), width: 0.8, height: 0.8)), with: .color(palette.ink.opacity(0.08)))
            }
        }
        ellipse(CGRect(x: 83, y: 133, width: 112, height: 112), fill: palette.accent.opacity(0.13))

        switch subject {
        case .mathematics:
            for x in stride(from: 76, through: 202, by: 18) {
                line([CGPoint(x: x, y: 135), CGPoint(x: x, y: 225)], width: 0.5, color: palette.ink.opacity(0.12))
            }
            for y in stride(from: 135, through: 225, by: 18) {
                line([CGPoint(x: 76, y: y), CGPoint(x: 202, y: y)], width: 0.5, color: palette.ink.opacity(0.12))
            }
            line([CGPoint(x: 72, y: 222), CGPoint(x: 205, y: 222)])
            line([CGPoint(x: 99, y: 230), CGPoint(x: 99, y: 128)])
            let curve = (0...70).map { value -> CGPoint in
                let t = Double(value) / 70
                return CGPoint(x: 103 + t * 93, y: 217 - t * t * 77)
            }
            line(curve, width: 2.2); text("f(x)", at: CGPoint(x: 178, y: 128), size: 18)
        case .science:
            for angle in [0.0, Double.pi / 3, -Double.pi / 3] {
                var orbit = Path(ellipseIn: CGRect(x: 71, y: 158, width: 122, height: 42))
                orbit = orbit.applying(CGAffineTransform(translationX: -center.x, y: -center.y)
                    .concatenating(CGAffineTransform(rotationAngle: angle))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                context.stroke(orbit, with: .color(stroke), lineWidth: 1.4)
            }
            ellipse(CGRect(x: 126, y: 173, width: 12, height: 12), fill: palette.ink.opacity(0.8))
            for point in [CGPoint(x: 79, y: 174), CGPoint(x: 157, y: 222), CGPoint(x: 159, y: 137)] {
                ellipse(CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6), fill: palette.accent)
            }
        case .history:
            line([CGPoint(x: 74, y: 151), CGPoint(x: 132, y: 124), CGPoint(x: 190, y: 151), CGPoint(x: 74, y: 151)])
            line([CGPoint(x: 80, y: 157), CGPoint(x: 184, y: 157)], width: 2)
            for x in [91, 125, 159] {
                box(CGRect(x: x, y: 163, width: 14, height: 58), radius: 2)
                line([CGPoint(x: x - 4, y: 163), CGPoint(x: x + 18, y: 163)])
            }
            box(CGRect(x: 76, y: 225, width: 112, height: 7), radius: 1)
            line([CGPoint(x: 70, y: 238), CGPoint(x: 194, y: 238)])
        case .biology:
            var stem = Path(); stem.move(to: CGPoint(x: 116, y: 238))
            stem.addQuadCurve(to: CGPoint(x: 148, y: 126), control: CGPoint(x: 143, y: 182))
            context.stroke(stem, with: .color(stroke), lineWidth: 1.8)
            for (x, y, side) in [(130.0, 207.0, -1.0), (139, 185, 1), (143, 161, -1), (147, 139, 1)] {
                var leaf = Path(); leaf.move(to: CGPoint(x: x, y: y))
                leaf.addQuadCurve(to: CGPoint(x: x + side * 36, y: y - 23), control: CGPoint(x: x + side * 43, y: y + 4))
                leaf.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x + side * 4, y: y - 36))
                context.fill(leaf, with: .color(palette.accent.opacity(0.3)))
                context.stroke(leaf, with: .color(stroke), lineWidth: 1.2)
            }
        case .chemistry:
            var flask = Path(); flask.move(to: CGPoint(x: 120, y: 130))
            for point in [CGPoint(x: 120, y: 163), CGPoint(x: 88, y: 218), CGPoint(x: 92, y: 230),
                          CGPoint(x: 172, y: 230), CGPoint(x: 176, y: 218), CGPoint(x: 144, y: 163), CGPoint(x: 144, y: 130)] {
                flask.addLine(to: point)
            }
            context.stroke(flask, with: .color(stroke), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            line([CGPoint(x: 116, y: 130), CGPoint(x: 148, y: 130)], width: 2)
            line([CGPoint(x: 103, y: 196), CGPoint(x: 161, y: 196)], color: palette.ink.opacity(0.35))
            for (x, y, size) in [(119.0, 210.0, 8.0), (146, 215, 5), (134, 179, 6), (155, 137, 7)] {
                ellipse(CGRect(x: x, y: y, width: size, height: size), fill: palette.accent.opacity(0.55))
            }
        case .physics:
            line([CGPoint(x: 69, y: 181), CGPoint(x: 199, y: 181)], width: 0.8, color: palette.ink.opacity(0.3))
            let wave = (0...120).map { step in
                CGPoint(x: 72 + Double(step), y: 181 - sin(Double(step) * .pi / 40) * 30)
            }
            line(wave, width: 2)
            line([CGPoint(x: 92, y: 230), CGPoint(x: 132, y: 213), CGPoint(x: 172, y: 230)], color: palette.ink.opacity(0.4))
            text("E = mc²", at: CGPoint(x: 132, y: 135), size: 18)
        case .literature:
            var book = Path(); book.move(to: CGPoint(x: 132, y: 151))
            book.addQuadCurve(to: CGPoint(x: 77, y: 144), control: CGPoint(x: 102, y: 130))
            book.addLine(to: CGPoint(x: 77, y: 218))
            book.addQuadCurve(to: CGPoint(x: 132, y: 226), control: CGPoint(x: 107, y: 208))
            book.addQuadCurve(to: CGPoint(x: 187, y: 218), control: CGPoint(x: 160, y: 208))
            book.addLine(to: CGPoint(x: 187, y: 144))
            book.addQuadCurve(to: CGPoint(x: 132, y: 151), control: CGPoint(x: 162, y: 130))
            book.addLine(to: CGPoint(x: 132, y: 226))
            context.stroke(book, with: .color(stroke), lineWidth: 1.6)
            for y in [164, 178, 192] {
                line([CGPoint(x: 88, y: y), CGPoint(x: 118, y: y + 3)], width: 0.9, color: palette.ink.opacity(0.35))
                line([CGPoint(x: 146, y: y + 3), CGPoint(x: 176, y: y)], width: 0.9, color: palette.ink.opacity(0.35))
            }
        case .geography:
            ellipse(CGRect(x: 80, y: 127, width: 104, height: 104))
            ellipse(CGRect(x: 105, y: 127, width: 54, height: 104))
            ellipse(CGRect(x: 80, y: 155, width: 104, height: 48))
            line([CGPoint(x: 80, y: 179), CGPoint(x: 184, y: 179)])
            line([CGPoint(x: 132, y: 127), CGPoint(x: 132, y: 231)])
        case .computing:
            box(CGRect(x: 72, y: 136, width: 122, height: 86), radius: 8)
            line([CGPoint(x: 72, y: 155), CGPoint(x: 194, y: 155)], width: 0.8)
            for x in [83, 91, 99] { ellipse(CGRect(x: x, y: 145, width: 3, height: 3), fill: palette.accent) }
            line([CGPoint(x: 111, y: 171), CGPoint(x: 98, y: 184), CGPoint(x: 111, y: 197)], width: 1.9)
            line([CGPoint(x: 153, y: 171), CGPoint(x: 166, y: 184), CGPoint(x: 153, y: 197)], width: 1.9)
            line([CGPoint(x: 138, y: 168), CGPoint(x: 126, y: 202)], width: 1.9)
        case .economics:
            line([CGPoint(x: 78, y: 135), CGPoint(x: 78, y: 229), CGPoint(x: 195, y: 229)])
            for (x, height) in [(94.0, 30.0), (128, 51), (162, 74)] {
                box(CGRect(x: x, y: 224 - height, width: 19, height: height), radius: 2, fill: palette.accent.opacity(0.24))
            }
            line([CGPoint(x: 89, y: 176), CGPoint(x: 123, y: 153), CGPoint(x: 155, y: 161), CGPoint(x: 189, y: 128)], width: 1.5)
        case .languages:
            box(CGRect(x: 73, y: 134, width: 86, height: 57), radius: 10, fill: palette.paper)
            box(CGRect(x: 119, y: 180, width: 75, height: 49), radius: 10, fill: palette.paper)
            line([CGPoint(x: 91, y: 191), CGPoint(x: 84, y: 202), CGPoint(x: 107, y: 191)])
            line([CGPoint(x: 165, y: 229), CGPoint(x: 179, y: 238), CGPoint(x: 179, y: 229)])
            text("hello", at: CGPoint(x: 116, y: 162), size: 17)
            text("hola", at: CGPoint(x: 157, y: 204), size: 17)
        case .art:
            var palettePath = Path(); palettePath.move(to: CGPoint(x: 158, y: 219))
            palettePath.addCurve(to: CGPoint(x: 83, y: 199), control1: CGPoint(x: 110, y: 242), control2: CGPoint(x: 68, y: 231))
            palettePath.addCurve(to: CGPoint(x: 174, y: 139), control1: CGPoint(x: 68, y: 146), control2: CGPoint(x: 136, y: 119))
            palettePath.addCurve(to: CGPoint(x: 158, y: 219), control1: CGPoint(x: 223, y: 168), control2: CGPoint(x: 124, y: 175))
            context.stroke(palettePath, with: .color(stroke), lineWidth: 1.5)
            let paints: [(CGFloat, CGFloat, Color)] = [(101, 171, Color(red: 0.72, green: 0.46, blue: 0.45)),
                                                     (123, 150, Color(red: 0.78, green: 0.66, blue: 0.36)),
                                                     (154, 151, Color(red: 0.45, green: 0.61, blue: 0.49))]
            for (x, y, color) in paints { ellipse(CGRect(x: x, y: y, width: 12, height: 12), fill: color.opacity(0.7)) }
            ellipse(CGRect(x: 145, y: 197, width: 12, height: 12))
        }
    }
}
