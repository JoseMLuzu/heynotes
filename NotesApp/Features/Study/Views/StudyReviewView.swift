import SwiftUI

struct StudyReviewView: View {
    let model: StudyViewModel
    let session: StudyReviewSession
    let openSource: (StudySource) -> Void
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var minimumCardHeight: CGFloat = 230

    var body: some View {
        NavigationStack {
            Group {
                if session.isComplete {
                    ContentUnavailableView {
                        Label(session.isPractice ? "Practice complete" : "A little more remembered.", systemImage: "checkmark.circle")
                    } description: {
                        if session.isPractice {
                            Text("\(session.reviewedCount) \(session.reviewedCount == 1 ? "card practiced" : "cards practiced"). Your scheduled review dates are unchanged.")
                        } else {
                            Text("\(session.reviewedCount) \(session.reviewedCount == 1 ? "card reviewed" : "cards reviewed"). Your progress is saved.")
                        }
                    } actions: {
                        if session.isPractice {
                            Button("Practice Again") { session.repeatPractice(in: model) }
                                .buttonStyle(.borderedProminent).disabled(!session.canRepeat(in: model))
                                .accessibilityIdentifier("study.practiceAgain")
                            Button("Done") { dismiss() }.buttonStyle(.bordered)
                        } else {
                            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                        }
                    }
                } else if let card = session.current(in: model) {
                    ViewThatFits(in: .vertical) {
                        review(card)
                        // Small heights and accessibility text scroll the full, stable arrangement.
                        ScrollView { review(card, scrolls: true) }
                    }
                } else {
                    VStack {
                        ContentUnavailableView("Card unavailable", systemImage: "rectangle.slash",
                                               description: Text("This card may have been moved to Trash."))
                        Button("Continue") { session.skip() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle(session.isPractice ? "Practice" : "Review").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .studyError($error)
        }.appSheetPresentation()
    }

    private func review(_ card: Flashcard, scrolls: Bool = false) -> some View {
        VStack(spacing: 18) {
            header(card)
            StudyReviewCard(question: card.question, answer: card.answer,
                            isAnswerVisible: session.isAnswerVisible, flip: session.flip)
                .frame(minHeight: minimumCardHeight, maxHeight: scrolls ? minimumCardHeight : .infinity)
                .id(card.id)
                .layoutPriority(1)
            StudyReviewControls(isAnswerVisible: session.isAnswerVisible, interval: {
                model.schedule(for: card, rating: $0, at: .now).progress.intervalSeconds
            }, flip: session.flip, practiceNext: session.isPractice ? {
                guard session.isAnswerVisible, session.current(in: model)?.id == card.id else { return }
                do { try session.advancePractice(model: model) }
                catch { self.error = error.localizedDescription }
            } : nil) { rating in
                guard session.isAnswerVisible, session.current(in: model)?.id == card.id else { return }
                do { try session.rate(rating, model: model) }
                catch { self.error = error.localizedDescription }
            }
            footer(card)
        }
        .padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private func header(_ card: Flashcard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack").foregroundStyle(AppTheme.accent).accessibilityHidden(true)
                Text(card.deck?.title ?? "Review").font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(session.index + 1) / \(session.cardIDs.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("Card \(session.index + 1) of \(session.cardIDs.count)")
            }
            ProgressView(value: Double(session.index), total: Double(max(1, session.cardIDs.count)))
                .tint(AppTheme.accent).accessibilityLabel("Session progress")
        }
    }

    private func footer(_ card: Flashcard) -> some View {
        HStack {
            if card.sourcePageID != nil {
                Button {
                    do { openSource(try model.source(for: card)) }
                    catch { self.error = error.localizedDescription }
                } label: { Label("Source Note", systemImage: "note.text") }
                    .accessibilityLabel("Open Source Note").accessibilityIdentifier("study.source")
            }
            Spacer(minLength: 8)
            Button { session.skip() } label: { Label("Skip", systemImage: "chevron.right") }
                .studyReviewAnchor("study.skip")
        }
        .font(.subheadline).foregroundStyle(.secondary).buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}
