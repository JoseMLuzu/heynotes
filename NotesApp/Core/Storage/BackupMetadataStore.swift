import Foundation
import SwiftData

/// Constructed on the backup service's executor; model objects never leave this actor.
@ModelActor actor BackupMetadataStore {
    func capture() throws -> BackupManifest {
        modelContext.autosaveEnabled = false
        return BackupManifest(
            folders: try modelContext.fetch(FetchDescriptor<Folder>()).map(BackupManifest.SavedFolder.init),
            notebooks: try modelContext.fetch(FetchDescriptor<Notebook>()).map(BackupManifest.SavedNotebook.init),
            sections: try modelContext.fetch(FetchDescriptor<NotebookSection>()).map(BackupManifest.SavedSection.init),
            pages: try modelContext.fetch(FetchDescriptor<NotePage>()).map(BackupManifest.SavedPage.init),
            decks: try modelContext.fetch(FetchDescriptor<StudyDeck>()).map(BackupManifest.SavedDeck.init),
            cards: try modelContext.fetch(FetchDescriptor<Flashcard>()).map(BackupManifest.SavedCard.init),
            reviews: try modelContext.fetch(FetchDescriptor<ReviewRecord>()).map(BackupManifest.SavedReview.init))
    }
}
