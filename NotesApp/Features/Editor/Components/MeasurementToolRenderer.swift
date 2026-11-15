import UIKit

enum MeasurementToolRenderer {
    static func protractor(_ points: [CGPoint], in context: CGContext) {
        guard let vertex = points.first else { return }
        let angle = points.count > 1 ? atan2(points[1].y - vertex.y, points[1].x - vertex.x) : 0
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: vertex.x, y: vertex.y); context.rotate(by: angle)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.6).cgColor); context.setLineWidth(1)
        context.addArc(center: .zero, radius: 100, startAngle: -.pi, endAngle: 0, clockwise: false); context.strokePath()
        context.move(to: CGPoint(x: -108, y: 0)); context.addLine(to: CGPoint(x: 108, y: 0)); context.strokePath()
        for degree in stride(from: 0, through: 180, by: 5) {
            let radians = -Double(degree) * .pi / 180, length: Double = degree % 10 == 0 ? 10 : 5
            context.move(to: CGPoint(x: cos(radians) * (100 - length), y: sin(radians) * (100 - length)))
            context.addLine(to: CGPoint(x: cos(radians) * 100, y: sin(radians) * 100)); context.strokePath()
        }
        context.rotate(by: -angle); context.translateBy(x: -vertex.x, y: -vertex.y)
        context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(2)
        for point in points.dropFirst() { context.move(to: vertex); context.addLine(to: point); context.strokePath() }
        context.setFillColor(UIColor.systemBlue.cgColor); context.fillEllipse(in: CGRect(x: vertex.x - 3, y: vertex.y - 3, width: 6, height: 6))
        if points.count == 3, let value = StudentToolGeometry.angle(vertex: vertex, first: points[1], second: points[2]) {
            label("\(value.formatted(.number.precision(.fractionLength(1))))°", at: CGPoint(x: vertex.x + 12, y: vertex.y + 12), in: context)
        } else { label(points.count == 1 ? "Tap first arm" : "Tap second arm", at: CGPoint(x: vertex.x + 12, y: vertex.y + 12), in: context) }
    }
    static func label(_ text: String, at point: CGPoint, in context: CGContext) {
        UIGraphicsPushContext(context); defer { UIGraphicsPopContext() }
        (text as NSString).draw(at: point, withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium), .foregroundColor: UIColor.systemBlue,
                                                           .backgroundColor: UIColor.white.withAlphaComponent(0.9)])
    }
}
