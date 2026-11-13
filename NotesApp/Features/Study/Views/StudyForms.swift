import SwiftUI

struct StudyDeckForm: View {
    let model: StudyViewModel
    let deck: StudyDeck?
    @State private var title: String
    @State private var notebookID: UUID?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(model: StudyViewModel, deck: StudyDeck? = nil, initialNotebookID: UUID? = nil) {
        self.model = model; self.deck = deck
        _title = State(initialValue: deck?.title ?? "")
        _notebookID = State(initialValue: deck?.notebookID ?? initialNotebookID)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Deck title", text: $title).accessibilityIdentifier("study.deckTitle")
                Section {
                    Picker("Notebook", selection: $notebookID) {
                        Text("Unlinked").tag(nil as UUID?)
                        ForEach(model.notebooks) { Text($0.title).tag(Optional($0.id)) }
                        if let notebookID, model.notebookTitle(notebookID) == nil {
                            Text("Unavailable notebook").tag(Optional(notebookID))
                        }
                    }
                } footer: { Text("Keep related decks together. Cards can also link to an individual page.") }
            }
            .navigationTitle(deck == nil ? "New Deck" : "Edit Deck").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try model.saveDeck(id: deck?.id, title: title, notebookID: notebookID); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .studyError($error)
        }.compactAppSheetPresentation(idealHeight: 320)
    }
}

struct FlashcardForm: View {
    let model: StudyViewModel
    let deck: StudyDeck
    let card: Flashcard?
    @State private var question: String
    @State private var answer: String
    @State private var notebookID: UUID?
    @State private var pageID: UUID?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(model: StudyViewModel, deck: StudyDeck, card: Flashcard? = nil, initialSource: StudySource? = nil) {
        self.model = model; self.deck = deck; self.card = card
        _question = State(initialValue: card?.question ?? "")
        _answer = State(initialValue: card?.answer ?? "")
        _notebookID = State(initialValue: card?.sourceNotebookID ?? initialSource?.notebookID ?? deck.notebookID)
        _pageID = State(initialValue: card?.sourcePageID ?? initialSource?.pageID)
    }
    private var pages: [NotePage] { model.notebooks.first { $0.id == notebookID }?.orderedPages ?? [] }
    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextEditor(text: $question).frame(minHeight: 100)
                        .accessibilityLabel("Question").accessibilityIdentifier("study.question")
                }
                Section("Answer") {
                    TextEditor(text: $answer).frame(minHeight: 160)
                        .accessibilityLabel("Answer").accessibilityIdentifier("study.answer")
                }
                Section {
                    Picker("Notebook", selection: $notebookID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(model.notebooks) { Text($0.title).tag(Optional($0.id)) }
                        if let notebookID, model.notebookTitle(notebookID) == nil {
                            Text("Unavailable notebook").tag(Optional(notebookID))
                        }
                    }.onChange(of: notebookID) { _, _ in pageID = nil }
                    if notebookID != nil {
                        Picker("Page", selection: $pageID) {
                            Text("No page link").tag(nil as UUID?)
                            ForEach(pages) { page in
                                Text("Page \(page.pageIndex + 1)\(page.bookmarkTitle.map { " — \($0)" } ?? "")")
                                    .tag(Optional(page.id))
                            }
                            if let pageID, !pages.contains(where: { $0.id == pageID }) {
                                Text("Unavailable page").tag(Optional(pageID))
                            }
                        }
                    }
                } header: { Text("Source Note · Optional") }
                  footer: { Text("Choose a page to return to your original notes while studying. Page links survive reordering.") }
            }
            .navigationTitle(card == nil ? "New Card" : "Edit Card").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let source = notebookID.flatMap { book in pageID.map { StudySource(notebookID: book, pageID: $0) } }
                        do {
                            try model.saveCard(id: card?.id, deckID: deck.id, question: question, answer: answer, source: source)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .studyError($error)
        }.appSheetPresentation()
    }
}

extension View {
    func studyError(_ message: Binding<String?>) -> some View {
        alert("Study", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK") { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}
