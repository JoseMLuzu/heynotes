import Foundation
import SwiftData

@MainActor
public enum PersistenceController {
    public static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NotesSchemaV6.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: NotesMigrationPlan.self, configurations: [configuration])
        // Mutations are saved explicitly, so callers can surface errors immediately.
        container.mainContext.autosaveEnabled = false
        return container
    }
}
