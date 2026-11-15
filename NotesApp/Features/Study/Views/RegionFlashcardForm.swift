import SwiftUI
import SwiftData

struct RegionFlashcardForm: View {
    let snapshot: CapturedPage
    let storage: DrawingStorage
    @State private var model: StudyViewModel
    @State private var question: CGRect?
    @State private var answer: CGRect?
    @State private var selectingAnswer = true
    @State private var questionCaption = ""
    @State private var answerCaption = ""
    @State private var deckID: UUID?
    @State private var newDeckTitle: String
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(snapshot: CapturedPage, initialRegion: CGRect, container: ModelContainer, storage: DrawingStorage) {
        self.snapshot = snapshot; self.storage = storage
        let model = StudyViewModel(container: container)
        _model = State(initialValue: model)
        _question = State(initialValue: snapshot.normalized(initialRegion))
        _deckID = State(initialValue: model.activeDecks.first { $0.notebookID == snapshot.source.notebookID }?.id)
        _newDeckTitle = State(initialValue: "\(snapshot.title) · Review")
    }
    private var valid: Bool {
        guard let question, let answer else { return false }
        return question.width >= 0.005 && question.height >= 0.005 && answer.width >= 0.005 && answer.height >= 0.005
            && (deckID != nil || !newDeckTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Select Region", selection: $selectingAnswer) {
                        Text("Question").tag(false); Text("Answer").tag(true)
                    }.pickerStyle(.segmented)
                    if let image = UIImage(data: snapshot.png) {
                        RegionSelectionCanvas(image: image, question: $question, answer: $answer, selectingAnswer: selectingAnswer)
                            .frame(maxHeight: 440).frame(maxWidth: .infinity)
                    }
                    Text(selectingAnswer ? "Drag across the answer region." : "Drag across the question region.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Use Whole Page") { setRegion(CGRect(x: 0, y: 0, width: 1, height: 1)) }
                        Button("Top Half") { setRegion(CGRect(x: 0, y: 0, width: 1, height: 0.5)) }
                        Button("Bottom Half") { setRegion(CGRect(x: 0, y: 0.5, width: 1, height: 0.5)) }
                    }.font(.caption)
                } header: { Text("Choose Question and Answer") }
                Section("Descriptions · Optional") {
                    TextField("Question description", text: $questionCaption, axis: .vertical)
                    TextField("Answer description", text: $answerCaption, axis: .vertical)
                    Text("Descriptions make captured cards easier to identify and use with VoiceOver.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Deck") {
                    Picker("Save To", selection: $deckID) {
                        Text("New deck").tag(nil as UUID?)
                        ForEach(model.activeDecks) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if deckID == nil { TextField("Deck title", text: $newDeckTitle) }
                    Label("Linked to \(snapshot.title)", systemImage: "note.text").font(.caption).foregroundStyle(.secondary)
                }
                if saving { HStack { ProgressView(); Text("Saving captured card…") } }
            }
            .disabled(saving)
            .navigationTitle("Card from Notes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving || !valid) }
            }
            .studyError($error)
        }
        .appSheetPresentation().interactiveDismissDisabled(saving)
    }
    private func setRegion(_ rect: CGRect) { if selectingAnswer { answer = rect } else { question = rect } }
    private func save() async {
        guard valid, let question, let answer else { return }
        saving = true; defer { saving = false }
        do {
            let images = try await StudyCaptureImages.shared.store(snapshot: snapshot, question: question, answer: answer, storage: storage)
            let destination: UUID
            if let deckID { destination = deckID }
            else {
                let deck = try model.saveDeck(title: newDeckTitle, notebookID: snapshot.source.notebookID)
                deckID = deck.id; destination = deck.id
            }
            try model.saveCard(deckID: destination,
                question: questionCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Question from \(snapshot.title)" : questionCaption,
                answer: answerCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Answer from notes" : answerCaption,
                source: snapshot.source, images: images)
            NotificationCenter.default.post(name: .studyContentChanged, object: nil)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
