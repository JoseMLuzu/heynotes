import SwiftUI

struct LibraryEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent.opacity(0.09))
                    .frame(width: 82, height: 108).rotationEffect(.degrees(-10)).offset(x: -10, y: 2)
                RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent.opacity(0.16)))
                    .frame(width: 82, height: 108)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "pencil.tip").font(.title2).foregroundStyle(AppTheme.accent)
                    Capsule().fill(AppTheme.accent.opacity(0.18)).frame(width: 34, height: 2)
                    Capsule().fill(AppTheme.accent.opacity(0.12)).frame(width: 24, height: 2)
                }
            }
            .frame(height: 128)
            .accessibilityHidden(true)
            VStack(spacing: 9) {
                Text(title).font(.system(.title2, design: .serif, weight: .medium))
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 300)
            }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}
