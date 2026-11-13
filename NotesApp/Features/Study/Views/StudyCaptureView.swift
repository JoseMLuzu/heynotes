import SwiftUI
import SwiftData

/// Manual card creation from a note, with a permanent source link already selected.
struct StudyCaptureView: View {
    @State private var model: StudyViewModel
    @State private var deck: StudyDeck?
    @State private var creatingDeck = false
    @Environment(\.dismiss) private var dismiss
    let source: StudySource

    init(context: ModelContext, source: StudySource) {
        _model = State(initialValue: StudyViewModel(container: context.container))
        self.source = source
    }

    private var orderedDecks: [StudyDeck] {
        model.activeDecks.sorted {
            let a = $0.notebookID == source.notebookID, b = $1.notebookID == source.notebookID
            return a == b ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : a
        }
    }

    var body: some View {
        Group {
            if let deck {
                FlashcardForm(model: model, deck: deck, initialSource: source)
            } else {
                NavigationStack {
                    List {
                        Section {
                            ForEach(orderedDecks) { item in
                                Button { deck = item } label: {
                                    Label(item.title, systemImage: "rectangle.stack")
                                }
                            }
                            Button { creatingDeck = true } label: { Label("New Deck", systemImage: "plus") }
                        } header: { Text("Choose a Deck") }
                          footer: { Text("Your new card will link to the current note page. Add its question and answer on the next screen.") }
                        if let error = model.loadError { Text(error).foregroundStyle(.secondary) }
                    }.navigationTitle("Create Flashcard").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }.appSheetPresentation()
            }
        }.sheet(isPresented: $creatingDeck) { StudyDeckForm(model: model, initialNotebookID: source.notebookID) }
    }
}
