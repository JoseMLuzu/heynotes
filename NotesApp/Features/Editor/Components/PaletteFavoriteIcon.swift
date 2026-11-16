import SwiftUI

/// Configuration stays legible without a separate badge floating outside the tool's hit area.
struct PaletteFavoriteIcon: View {
    let favorite: ToolPreset
    let selected: Bool
    var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: favorite.tool.symbol).font(.system(size: 21, weight: .regular))
                .foregroundStyle(selected || dropTargeted ? AppTheme.accent : .primary)
                .frame(height: 23)
            if favorite.tool.usesInkStyle {
                HStack(spacing: 3) {
                    Capsule().fill(favorite.ink.color).frame(width: 11, height: 3)
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                    Text(favorite.ink.width, format: .number.precision(.fractionLength(0...1)))
                        .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary).lineLimit(1)
                }.frame(height: 9)
            } else if favorite.tool == .eraser {
                Text(favorite.eraserMode == .strokes ? "Stroke" : favorite.eraserWidth.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 8, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    .frame(height: 9)
            }
        }
        .frame(width: QuickPaletteLayout.cellSize, height: QuickPaletteLayout.cellSize)
        .background(dropTargeted ? AppTheme.accent.opacity(0.24) : selected ? AppTheme.accent.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(
            dropTargeted ? AppTheme.accent : selected ? AppTheme.accent.opacity(contrast == .increased ? 0.7 : 0.32) : .primary.opacity(contrast == .increased ? 0.22 : 0.045),
            lineWidth: dropTargeted ? 2 : 1))
        .shadow(color: AppTheme.accent.opacity(dropTargeted ? 0.18 : 0), radius: 5, y: 1)
        .scaleEffect(dropTargeted && !reduceMotion ? 1.05 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: dropTargeted)
        .contentShape(Rectangle())
    }
}
