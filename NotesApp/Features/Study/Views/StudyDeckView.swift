import SwiftUI

struct StudyDeckView: View {
    let model: StudyViewModel
    let deck: StudyDeck
    let openSource: (StudySource) async -> Void
    @State private var creatingCard = false
    @State private var editingDeck = false
    @State private var editingCard: Flashcard?
    @State private var deletingCard: Flashcard?
    @State private var deletingDeck = false
    @State private var review: StudyReviewSession?
    @State private var pendingSource: StudySource?
    @State private var error: String?
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let now = Date.now
            let cards = model.cards(in: deck)
            let due = model.due(at: now, deckID: deck.id)
            List {
                Section {
                    if let title = model.notebookTitle(deck.notebookID) {
                        Label(title, systemImage: "book.closed").foregroundStyle(.secondary)
                    } else if deck.notebookID != nil { Text("Linked notebook unavailable").foregroundStyle(.secondary) }
                    LabeledContent("Cards", value: "\(cards.count)")
                    LabeledContent("Due now", value: "\(due.count)")
                    if !due.isEmpty {
                        Button { review = StudyReviewSession(cards: due) } label: { Label("Review Due Cards", systemImage: "play.fill") }
                    }
                    if !cards.isEmpty {
                        Button { review = StudyReviewSession(cards: cards, mode: .practice) } label: {
                            Label("Practice All · \(cards.count) cards", systemImage: "arrow.clockwise")
                        }.accessibilityIdentifier("study.practiceAll")
                        Text("Practice anytime without changing your review dates.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if cards.isEmpty {
                    ContentUnavailableView {
                        Label("One idea per card", systemImage: "rectangle.on.rectangle")
                    } description: { Text("Write a question and an answer, then return for a short review.") }
                    actions: { Button("Add Card") { creatingCard = true } }
                } else {
                    Section("Cards") {
                        ForEach(cards.filter { search.isEmpty || $0.question.localizedStandardContains(search) || $0.answer.localizedStandardContains(search) }) { card in
                            Button { editingCard = card } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(card.question).font(.headline).foregroundStyle(.primary).lineLimit(3)
                                    HStack {
                                        Text(card.nextReviewAt <= now ? "Due now" : "Next: \(card.nextReviewAt.formatted(date: .abbreviated, time: .shortened))")
                                        if card.sourcePageID != nil { Image(systemName: "link") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }.contextMenu {
                                Button("Edit Card", systemImage: "pencil") { editingCard = card }
                                if card.sourcePageID != nil {
                                    Button("Open Source Note", systemImage: "note.text") {
                                        do { let source = try model.source(for: card); Task { await openSource(source) } }
                                        catch { self.error = error.localizedDescription }
                                    }
                                }
                                Button("Move to Trash", systemImage: "trash", role: .destructive) { deletingCard = card }
                            }
                            .swipeActions { Button("Trash", role: .destructive) { deletingCard = card } }
                        }
                    }
                }
            }.searchable(text: $search, prompt: "Search cards")
        }
        .navigationTitle(deck.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Deck", systemImage: "pencil") { editingDeck = true }
                    Button("Move Deck to Trash", systemImage: "trash", role: .destructive) { deletingDeck = true }
                } label: { Label("Deck Options", systemImage: "ellipsis") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { creatingCard = true } label: { Label("New Card", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $creatingCard) { FlashcardForm(model: model, deck: deck) }
        .sheet(isPresented: $editingDeck) { StudyDeckForm(model: model, deck: deck) }
        .sheet(item: $editingCard) { FlashcardForm(model: model, deck: deck, card: $0) }
        .sheet(item: $review, onDismiss: {
            if let source = pendingSource { pendingSource = nil; Task { await openSource(source) } }
        }) { session in
            StudyReviewView(model: model, session: session) { source in pendingSource = source; review = nil }
        }
        .confirmationDialog("Move card to Trash?", isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let card = deletingCard { do { try model.trash(card) } catch { self.error = error.localizedDescription } }
                deletingCard = nil
            }
        } message: { Text("You can restore this card and its review history from Study Trash.") }
        .confirmationDialog("Move deck to Trash?", isPresented: $deletingDeck, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                do { try model.trash(deck); dismiss() } catch { self.error = error.localizedDescription }
            }
        } message: { Text("This deck and its \(model.cards(in: deck).count) cards will be hidden from Study. Restore them together from Study Trash.") }
        .studyError($error)
    }
}
