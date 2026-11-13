import SwiftUI

struct StudyReviewControls: View {
    let isAnswerVisible: Bool
    let interval: (ReviewRating) -> Double
    let flip: () -> Void
    var practiceNext: (() -> Void)? = nil
    let rate: (ReviewRating) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var minimumRatingWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 14) {
            Button(action: flip) {
                ZStack {
                    flipLabel("Reveal Answer").opacity(isAnswerVisible ? 0 : 1)
                    flipLabel("View Question").opacity(isAnswerVisible ? 1 : 0)
                }.frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(QuietPressStyle()).foregroundStyle(AppTheme.accent)
            .accessibilityLabel(isAnswerVisible ? "View Question" : "Reveal Answer")
            .studyReviewAnchor("study.flip")
            ZStack {
                // Keep the real grid in layout on both faces, including Dynamic Type row heights.
                VStack(spacing: 10) {
                  if let practiceNext {
                    Text("Practice · Your review dates stay unchanged")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(action: practiceNext) {
                        Label("Next Card", systemImage: "arrow.right")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                            .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(QuietPressStyle()).foregroundStyle(AppTheme.accent)
                    .disabled(!isAnswerVisible).accessibilityIdentifier("study.practiceNext")
                  } else {
                    Text("How well did you remember?").font(.caption).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        ratingRow(ReviewRating.allCases)
                        VStack(spacing: 10) {
                            ratingRow(Array(ReviewRating.allCases.prefix(2)))
                            ratingRow(Array(ReviewRating.allCases.suffix(2)))
                        }
                        VStack(spacing: 10) {
                            ForEach(ReviewRating.allCases) { rating in ratingButton(rating) }
                        }
                    }
                  }
                }
                .opacity(isAnswerVisible ? 1 : 0)
                .allowsHitTesting(isAnswerVisible).accessibilityHidden(!isAnswerVisible)
                VStack(spacing: 6) {
                    Text("A moment to remember.").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text("Recall your answer, then turn the card.").font(.caption).foregroundStyle(.tertiary)
                }
                .multilineTextAlignment(.center)
                .opacity(isAnswerVisible ? 0 : 1).accessibilityHidden(isAnswerVisible)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isAnswerVisible)
        }
    }

    private func ratingRow(_ ratings: [ReviewRating]) -> some View {
        HStack(spacing: 10) {
            ForEach(ratings) { rating in ratingButton(rating).frame(minWidth: minimumRatingWidth) }
        }
    }

    private func flipLabel(_ title: String) -> some View {
        Label(title, systemImage: "arrow.triangle.2.circlepath")
            .font(.headline).padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityHidden(true)
    }

    private func ratingButton(_ rating: ReviewRating) -> some View {
        let style = appearance(rating)
        let duration = intervalLabel(interval(rating))
        return Button { rate(rating) } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: style.symbol).font(.caption.weight(.semibold)).foregroundStyle(style.color)
                    Text(rating.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                }
                Text(duration).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 14).frame(maxWidth: .infinity)
                .background(style.color.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.065)))
        }
        .buttonStyle(QuietPressStyle())
        .disabled(!isAnswerVisible)
        .accessibilityLabel("\(rating.title), review in \(duration)")
        .accessibilityIdentifier("study.rate.\(rating.rawValue)")
    }

    private func appearance(_ rating: ReviewRating) -> (symbol: String, color: Color) {
        switch rating {
        case .again: ("arrow.counterclockwise", .red)
        case .hard: ("minus", .orange)
        case .good: ("checkmark", .green)
        case .easy: ("bolt", AppTheme.accent)
        }
    }

    private func intervalLabel(_ seconds: Double) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        let days = seconds / 86_400
        return "\(days.formatted(.number.precision(.fractionLength(0...1)))) \(days == 1 ? "day" : "days")"
    }
}
