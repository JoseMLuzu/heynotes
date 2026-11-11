import SwiftUI

struct TemplatePreview: View {
    let template: PaperTemplate
    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                cg.scaleBy(x: size.width / 768, y: size.height / 1086)
                TemplateRenderer.draw(template, size: CGSize(width: 768, height: 1086), in: cg)
            }
        }
        .aspectRatio(768.0 / 1086.0, contentMode: .fit)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2)))
        .accessibilityHidden(true)
    }
}
