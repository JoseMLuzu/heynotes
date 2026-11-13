import SwiftUI
import SwiftData

struct StudyView: View {
    @State private var model: StudyViewModel
    @State private var creatingDeck = false
    @State private var showingTrash = false
    @State private var review: StudyReviewSession?
    @State private var pendingSource: StudySource?
    @Environment(\.scenePhase) private var scenePhase
    let openSource: (StudySource) async -> Void

    init(context: ModelContext, openSource: @escaping (StudySource) async -> Void) {
        _model = State(initialValue: StudyViewModel(container: context.container))
        self.openSource = openSource
    }

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let now = Date.now
            let due = model.due(at: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("A little practice.\nA lasting memory.")
                            .font(.system(.largeTitle, design: .serif)).fontWeight(.medium)
                        HStack(spacing: 24) {
                            StudyCount(value: model.dueTodayCount(at: now), title: "Due today")
                            StudyCount(value: model.activeCards.count, title: "Total cards")
                            StudyCount(value: model.activeDecks.count, title: "Decks")
                        }
                        if !due.isEmpty {
                            Button { review = StudyReviewSession(cards: due) } label: {
                                Label("Review \(due.count) \(due.count == 1 ? "Card" : "Cards")", systemImage: "play.fill")
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                                .accessibilityIdentifier("study.reviewAll")
                        } else if !model.activeCards.isEmpty {
                            Label(model.dueTodayCount(at: now) == 0 ? "You're up to date" : "Nothing due right now",
                                  systemImage: "checkmark.circle").foregroundStyle(.secondary)
                            if let next = model.activeCards.map(\.nextReviewAt).min() {
                                Text("Next review: \(next.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
                    if let error = model.loadError {
                        ContentUnavailableView { Label("Unable to Load Study", systemImage: "exclamationmark.triangle") }
                        description: { Text(error) } actions: { Button("Try Again") { model.reload() } }
                    } else if model.activeDecks.isEmpty {
                        ContentUnavailableView {
                            Label("Keep what you learn", systemImage: "rectangle.stack")
                        } description: { Text("Create a deck, add a few cards and make your notes easier to remember.") }
                        actions: { Button("Create Deck") { creatingDeck = true }.buttonStyle(.bordered) }
                    } else {
                        Text("Your Decks").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                            ForEach(model.activeDecks) { deck in
                                NavigationLink(value: StudyRoute(deckID: deck.id)) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(AppTheme.accent)
                                        Text(deck.title).font(.headline).foregroundStyle(.primary)
                                            .lineLimit(2).frame(minHeight: 44, alignment: .topLeading)
                                        Text(model.notebookTitle(deck.notebookID) ?? (deck.notebookID == nil ? "Independent deck" : "Notebook unavailable"))
                                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                        Text("\(model.cards(in: deck).count) cards · \(model.due(at: now, deckID: deck.id).count) due")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.quaternary))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingTrash = true } label: { Label("Study Trash", systemImage: "trash") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { creatingDeck = true } label: { Label("New Deck", systemImage: "plus") }
            }
        }
        .navigationDestination(for: StudyRoute.self) { route in
            if let deck = model.activeDecks.first(where: { $0.id == route.deckID }) {
                StudyDeckView(model: model, deck: deck, openSource: openSource)
            } else {
                ContentUnavailableView("Deck unavailable", systemImage: "rectangle.stack",
                                       description: Text("This deck may have been moved to Study Trash."))
            }
        }
        .sheet(isPresented: $creatingDeck) { StudyDeckForm(model: model) }
        .sheet(isPresented: $showingTrash) { StudyTrashView(model: model) }
        .sheet(item: $review, onDismiss: {
            if let source = pendingSource { pendingSource = nil; Task { await openSource(source) } }
        }) { session in
            StudyReviewView(model: model, session: session) { source in pendingSource = source; review = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload() } }
    }
}

private struct StudyCount: View {
    let value: Int
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value, format: .number).font(.title.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
