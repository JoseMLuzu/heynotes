import SwiftUI

struct ColorChoiceButton: View {
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Circle().fill(color).frame(width: 34, height: 34)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark").font(.caption.bold())
                                .foregroundStyle(colorScheme == .dark ? .black : .white)
                        }
                    }
                Text(title).font(.caption2).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(minWidth: 64, minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
