import SwiftUI

struct RegionSelectionCanvas: View {
    let image: UIImage
    @Binding var question: CGRect?
    @Binding var answer: CGRect?
    let selectingAnswer: Bool

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        if let question { outline(question, color: .blue, label: "Q", in: geometry.size) }
                        if let answer { outline(answer, color: .orange, label: "A", in: geometry.size) }
                        Color.clear.contentShape(Rectangle())
                            .highPriorityGesture(DragGesture(minimumDistance: 4)
                                .onChanged { drag in
                                    let rect = CGRect(x: min(drag.startLocation.x, drag.location.x), y: min(drag.startLocation.y, drag.location.y),
                                                      width: abs(drag.location.x - drag.startLocation.x), height: abs(drag.location.y - drag.startLocation.y))
                                    let unit = CGRect(x: rect.minX / geometry.size.width, y: rect.minY / geometry.size.height,
                                                      width: rect.width / geometry.size.width, height: rect.height / geometry.size.height)
                                        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                                    guard !unit.isNull else { return }
                                    if selectingAnswer { answer = unit } else { question = unit }
                                })
                    }
                }
            }
            .accessibilityLabel("Source page. Use the region controls below as an alternative to dragging.")
    }
    private func outline(_ rect: CGRect, color: Color, label: String, in size: CGSize) -> some View {
        Rectangle().fill(color.opacity(0.12)).overlay(Rectangle().strokeBorder(color, lineWidth: 2))
            .overlay(alignment: .topLeading) { Text(label).font(.caption.bold()).padding(4).background(color).foregroundStyle(.white) }
            .frame(width: rect.width * size.width, height: rect.height * size.height)
            .offset(x: rect.minX * size.width, y: rect.minY * size.height).allowsHitTesting(false)
    }
}
