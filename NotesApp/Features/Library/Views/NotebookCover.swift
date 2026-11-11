import SwiftUI

/// A quiet, book-like cover shared by the library and the live creation preview.
struct NotebookCover: View {
    let title: String
    let color: CoverColor
    var style: CoverStyle? = nil
    var isPDF = false
    var favorite = false
    @Environment(\.colorScheme) private var colorScheme

    private var initial: String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12).fill(color.color)
                if let subject = style?.subject {
                    SubjectNotebookCover(subject: subject, badgeSpace: favorite || isPDF)
                } else if let style, let artwork = CoverArtwork.image(for: style) {
                    Image(uiImage: artwork).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Rectangle().fill(.black.opacity(0.09)).frame(width: 8).padding(.leading, 9)
                    Rectangle().fill(.white.opacity(0.13)).frame(width: 1).padding(.leading, 18)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(isPDF ? "DOCUMENT" : "NOTEBOOK")
                                .font(.system(size: max(9, geometry.size.width * 0.044), weight: .medium))
                                .tracking(2)
                            Spacer(minLength: 0)
                            if favorite { Image(systemName: "star.fill").font(.caption2) }
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        Spacer(minLength: 8)
                        Text(initial.isEmpty ? "N" : initial)
                            .font(.system(size: geometry.size.height * 0.36, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.94))
                        Spacer(minLength: 8)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.65)).frame(width: 24, height: 2)
                            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.24)).frame(width: 8, height: 2)
                        }
                    }
                    .padding(.leading, geometry.size.width * 0.17)
                    .padding(.trailing, geometry.size.width * 0.12)
                    .padding(.vertical, geometry.size.height * 0.13)
                }
                if (style?.artworkIndex != nil || style?.subject != nil) && (favorite || isPDF) {
                    HStack(spacing: style?.subject != nil ? 4 : 6) {
                        if isPDF { Image(systemName: "doc.richtext") }
                        if favorite { Image(systemName: "star.fill") }
                    }
                    .font(style?.subject != nil ? .system(size: max(8, geometry.size.width * 0.065)) : .caption)
                    .padding(style?.subject != nil ? 6 : 8).background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                if style?.artworkIndex == nil && style?.subject == nil {
                    RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.28)).frame(height: 2).padding(.horizontal, 9).padding(.bottom, 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.09), radius: 8, x: 0, y: 5)
        }
        .aspectRatio(0.82, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
