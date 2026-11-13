import SwiftUI

/// Both faces share one viewport; rotation affects drawing, never the surrounding layout.
struct StudyReviewCard: View {
    let question: String
    let answer: String
    let isAnswerVisible: Bool
    let flip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            face(question, answer: false)
                .modifier(ReviewFaceRotation(angle: angle, front: true))
                .accessibilityHidden(isAnswerVisible)
                .allowsHitTesting(!isAnswerVisible)
            face(answer, answer: true)
                .modifier(ReviewFaceRotation(angle: angle, front: false))
                .accessibilityHidden(!isAnswerVisible)
                .allowsHitTesting(isAnswerVisible)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isAnswerVisible)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture(perform: flip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flashcard")
        .accessibilityValue(isAnswerVisible ? "Answer" : "Question")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isAnswerVisible ? "Activate to return to the question" : "Activate to reveal the answer")
        .accessibilityAction { flip() }
        .studyReviewAnchor("study.card")
    }

    private var angle: Double { isAnswerVisible ? 180 : 0 }

    private func face(_ text: String, answer: Bool) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: answer ? "text.bubble" : "questionmark.bubble")
                Text(answer ? "Answer" : "Question")
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.accent)
            .accessibilityHidden(true)
            GeometryReader { geometry in
                ScrollView {
                    Text(text)
                        .font(.system(answer ? .title3 : .title2, design: .rounded).weight(answer ? .regular : .medium))
                        .multilineTextAlignment(.center).lineSpacing(6).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                        .accessibilityIdentifier(answer ? "study.answerText" : "study.questionText")
                }
            }
            Text(answer ? "Tap to return to the question" : "Tap the card to reveal the answer")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .padding(24)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(AppTheme.accent.opacity(0.12)))
        .shadow(color: .black.opacity(0.035), radius: 16, y: 6)
    }
}

/// Animatable + ViewModifier avoids the deprecated AnimatableModifier protocol.
private nonisolated struct ReviewFaceRotation: ViewModifier, Animatable {
    var angle: Double
    let front: Bool
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View {
        content
            .opacity(front ? (angle < 90 ? 1 : 0) : (angle >= 90 ? 1 : 0))
            .rotation3DEffect(.degrees(angle + (front ? 0 : 180)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}
