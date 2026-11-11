import SwiftUI

struct ToolOptionsPanel: View {
    @Bindable var preferences: ToolPreferences
    let clearInk: () -> Void
    @State private var confirmingClear = false
    @Environment(\.dismiss) private var dismiss

    private let palette: [(String, Color)] = [
        ("Black", Color(red: 0.08, green: 0.09, blue: 0.09)), ("Graphite", Color(white: 0.4)),
        ("Blue", Color(red: 0.15, green: 0.35, blue: 0.8)), ("Sky", .cyan),
        ("Teal", .teal), ("Forest", Color(red: 0.2, green: 0.45, blue: 0.3)),
        ("Purple", .purple), ("Rose", .pink), ("Red", .red), ("Orange", .orange),
        ("Amber", Color(red: 0.95, green: 0.65, blue: 0.1)), ("Yellow", .yellow)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(preferences.selected.title, systemImage: preferences.selected.symbol).font(.headline)
                Spacer()
                Button("Done") { dismiss() }.frame(minHeight: 44)
            }.padding(.horizontal, 20).padding(.top, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if preferences.selected.usesInkStyle { inkOptions }
                    else if preferences.selected == .eraser { eraserOptions }
                    else {
                        Text(preferences.selected == .lasso ? "Draw a loop around handwriting with Apple Pencil, then drag the selection to move it. Touch and hold selected ink for editing actions." : "Drag on the page to create study tape. Choose Select Objects to move or resize inserted content. Tap tape with a finger to reveal or cover the answer.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if preferences.selected.usesInkStyle || preferences.selected == .eraser {
                        Button("Reset This Tool") { preferences.resetCurrentTool() }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                }.padding(20)
            }
        }
        .frame(width: 336, height: preferences.selected == .lasso ? 240 : 540)
        .presentationCompactAdaptation(.popover)
        .confirmationDialog("Clear all handwriting on this page?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Handwriting", role: .destructive) { clearInk(); dismiss() }
        } message: { Text("The page background stays. Use Undo to restore the handwriting during this canvas session.") }
    }

    private var inkOptions: some View {
        Group {
            strokePreview
            VStack(alignment: .leading, spacing: 10) {
                widthHeader("Width", value: preferences.ink.width)
                Slider(value: Binding(get: { preferences.ink.width }, set: { preferences.ink.width = $0 }), in: preferences.widthRange)
                    .accessibilityLabel("Stroke Width")
                widthPresets(preferences.selected == .marker ? [5, 8, 12, 18, 24, 36] : [0.5, 1, 2, 3, 5, 8], range: preferences.widthRange,
                             current: preferences.ink.width) { preferences.ink.width = $0 }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Opacity").font(.subheadline.weight(.medium)); Spacer(); Text(preferences.ink.opacity, format: .percent.precision(.fractionLength(0))).font(.caption).foregroundStyle(.secondary) }
                Slider(value: Binding(get: { preferences.ink.opacity }, set: { preferences.ink.opacity = $0 }), in: 0.1...1, step: 0.05)
                    .accessibilityLabel("Ink Opacity")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Colors").font(.subheadline.weight(.medium))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(palette, id: \.0) { name, color in
                        let selected = preferences.matchesColor(color)
                        Button { preferences.setColor(color) } label: {
                            Circle().fill(color).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(selected ? AppTheme.accent : .clear, lineWidth: 2).padding(2))
                        }
                        .buttonStyle(QuietPressStyle())
                        .accessibilityLabel(name).accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                ColorPicker("Custom Color", selection: Binding(get: { preferences.ink.color }, set: { preferences.setColor($0) }), supportsOpacity: false)
                    .font(.subheadline).frame(minHeight: 44)
            }
        }
    }

    private var eraserOptions: some View {
        Group {
            Picker("Eraser Mode", selection: $preferences.eraserMode) {
                ForEach(EraserMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text(preferences.eraserMode == .strokes ? "Remove an entire stroke when you touch it." : "Erase only the part you touch, with a fixed-size eraser.")
                .font(.subheadline).foregroundStyle(.secondary)
            if preferences.eraserMode == .precise {
                VStack(alignment: .leading, spacing: 12) {
                    widthHeader("Eraser Size", value: preferences.eraserWidth)
                    Slider(value: $preferences.eraserWidth, in: preferences.eraserRange)
                        .accessibilityLabel("Eraser Size")
                    widthPresets([5, 10, 20, 30, 50, 80], range: preferences.eraserRange, current: preferences.eraserWidth) { preferences.eraserWidth = $0 }
                    Circle().strokeBorder(.secondary, lineWidth: 1)
                        .frame(width: min(80, preferences.eraserWidth), height: min(80, preferences.eraserWidth))
                        .frame(maxWidth: .infinity, minHeight: 88).accessibilityHidden(true)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button("Clear Page Handwriting", role: .destructive) { confirmingClear = true }.frame(minHeight: 44)
                Text("Keeps the paper and PDF background. You can undo this action.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var strokePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 24, y: size.height * 0.65))
                path.addCurve(to: CGPoint(x: size.width - 24, y: size.height * 0.4),
                              control1: CGPoint(x: size.width * 0.35, y: -8), control2: CGPoint(x: size.width * 0.6, y: size.height + 8))
                context.stroke(path, with: .color(preferences.ink.color.opacity(preferences.ink.opacity)),
                               style: StrokeStyle(lineWidth: min(36, preferences.ink.width), lineCap: .round))
            }
            .frame(height: 72).background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.gray.opacity(0.2)))
            .accessibilityHidden(true)
            Text("Width preview. Pressure and tilt can change the stroke.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func widthHeader(_ title: String, value: Double) -> some View {
        HStack { Text(title).font(.subheadline.weight(.medium)); Spacer(); Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) pt").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
    }

    private func widthPresets(_ values: [Double], range: ClosedRange<Double>, current: Double, action: @escaping (Double) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(values.filter { range.contains($0) }, id: \.self) { value in
                Button { action(value) } label: {
                    Text(value, format: .number.precision(.fractionLength(0...1))).font(.caption.monospacedDigit())
                        .frame(minWidth: 40, minHeight: 44)
                        .background(abs(current - value) < 0.01 ? AppTheme.accent.opacity(0.12) : AppTheme.controlSurface, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain).accessibilityLabel("\(value) points")
                .accessibilityAddTraits(abs(current - value) < 0.01 ? .isSelected : [])
            }
        }
    }
}
