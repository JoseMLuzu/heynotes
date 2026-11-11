import SwiftUI

struct NotebookCoverFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct DocumentOpeningSource {
    let id: UUID
    let frame: CGRect
}

/// Only compositor transforms animate: the live canvas keeps its final layout throughout.
struct DocumentOpeningZoom: ViewModifier {
    static let duration = 0.22
    let sourceFrame: CGRect
    let progress: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let destination = geometry.frame(in: .global)
            let initialScale = min(1, max(0.12, min(
                sourceFrame.width / max(1, destination.width),
                sourceFrame.height / max(1, destination.height))))
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(initialScale + (1 - initialScale) * progress)
                .offset(x: (sourceFrame.midX - destination.midX) * (1 - progress),
                        y: (sourceFrame.midY - destination.midY) * (1 - progress))
                .opacity(0.15 + 0.85 * progress)
        }
    }
}
