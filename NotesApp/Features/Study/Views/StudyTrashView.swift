import SwiftUI

struct StudyTrashView: View {
    let model: StudyViewModel
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var decks: [StudyDeck] { model.decks.filter { $0.trashedAt != nil } }
    private var cards: [Flashcard] { model.cards.filter { $0.trashedAt != nil && $0.deck?.trashedAt == nil } }
    var body: some View {
        NavigationStack {
            List {
                if decks.isEmpty && cards.isEmpty {
                    ContentUnavailableView("Study Trash is empty", systemImage: "trash",
                                           description: Text("Deleted decks and cards can be restored here."))
                }
                if !decks.isEmpty {
                    Section("Decks") {
                        ForEach(decks) { deck in
                            HStack {
                                VStack(alignment: .leading) { Text(deck.title); Text("\(deck.cards.count) cards").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("Restore") { do { try model.restore(deck) } catch { self.error = error.localizedDescription } }
                                    .accessibilityLabel("Restore \(deck.title)")
                            }
                        }
                    }
                }
                if !cards.isEmpty {
                    Section("Cards") {
                        ForEach(cards) { card in
                            HStack {
                                Text(card.question).lineLimit(3); Spacer()
                                Button("Restore") { do { try model.restore(card) } catch { self.error = error.localizedDescription } }
                                    .accessibilityLabel("Restore \(card.question)")
                            }
                        }
                    }
                }
            }.navigationTitle("Study Trash").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .studyError($error)
        }.appSheetPresentation()
    }
}
