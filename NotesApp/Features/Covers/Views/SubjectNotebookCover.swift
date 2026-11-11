import SwiftUI

/// Resolution-independent subject artwork, bundled as drawing code rather than image files.
struct SubjectNotebookCover: View {
    let subject: NotebookSubject
    var badgeSpace = false
    private var palette: SubjectCoverPalette { SubjectCoverPalette(subject) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                palette.paper
                Canvas { context, size in
                    var drawing = context
                    drawing.scaleBy(x: size.width / 240, y: size.height / 300)
                    SubjectCoverIllustration.draw(subject, palette: palette, context: drawing)
                }
                Rectangle().fill(palette.ink.opacity(0.07)).frame(width: geometry.size.width * 0.035)
                    .padding(.leading, geometry.size.width * 0.035)
                Rectangle().fill(.white.opacity(0.45)).frame(width: 1)
                    .padding(.leading, geometry.size.width * 0.075)
                VStack(alignment: .leading, spacing: geometry.size.height * 0.025) {
                    Text("SUBJECT NOTES")
                        .font(.system(size: geometry.size.width * 0.034, weight: .medium)).tracking(1.8)
                        .foregroundStyle(palette.ink.opacity(0.6))
                    Text(subject.title)
                        .font(.system(size: geometry.size.width * 0.105, weight: .medium, design: .serif))
                        .lineLimit(2).minimumScaleFactor(0.75)
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text(subject.subtitle)
                        .font(.system(size: geometry.size.width * 0.043, weight: .regular))
                        .foregroundStyle(palette.ink.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .padding(.leading, geometry.size.width * 0.15)
                .padding(.trailing, geometry.size.width * 0.10)
                .padding(.top, geometry.size.height * (badgeSpace ? 0.20 : 0.12))
                .padding(.bottom, geometry.size.height * 0.10)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SubjectCoverPalette {
    let paper: Color
    let ink: Color
    let accent: Color
    init(_ subject: NotebookSubject) {
        let values: (UInt32, UInt32, UInt32) = switch subject {
        case .mathematics: (0xE4EDF5, 0x365B79, 0x92B2CD)
        case .science: (0xE5EEE8, 0x416455, 0xA0B9A5)
        case .history: (0xF0E6D7, 0x7A5C40, 0xC5A17A)
        case .biology: (0xE5EBDD, 0x4A6545, 0xA3B596)
        case .chemistry: (0xEBE5F1, 0x6E587F, 0xBAA6CB)
        case .physics: (0xE0EAF0, 0x35576C, 0x94B5BF)
        case .literature: (0xF0E1E0, 0x855C60, 0xCAA3A3)
        case .geography: (0xE0ECE7, 0x426960, 0x9BB8A7)
        case .computing: (0xE3E7EE, 0x46576E, 0x9DABC0)
        case .economics: (0xEEE9D9, 0x736843, 0xBCB080)
        case .languages: (0xE3EBF0, 0x506D87, 0xA5BACB)
        case .art: (0xF3E4DC, 0x936954, 0xD6B19A)
        }
        func color(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
        }
        paper = color(values.0); ink = color(values.1); accent = color(values.2)
    }
}
