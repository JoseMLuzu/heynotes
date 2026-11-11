import SwiftData

@MainActor
struct AppDependencies {
    let container: ModelContainer

    init() throws {
        container = try PersistenceController.makeContainer()
    }
}
