import Foundation
import SwiftData

/// Explicit development operation; never runs during an ordinary app launch.
@MainActor enum StudySampleDeck {
    struct Result { let id: UUID; let cardCount: Int; let trashed: Bool }
    static let id = UUID(uuidString: "7791E314-7164-41E0-88E3-E08AD30EF5FA")!

    static func create(in container: ModelContainer, now: Date = .now) throws -> Result {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let deckID = id
        var request = FetchDescriptor<StudyDeck>(predicate: #Predicate { $0.id == deckID })
        request.fetchLimit = 1
        // Re-running the operation must not duplicate cards or reset review progress.
        if let existing = try context.fetch(request).first {
            return Result(id: existing.id, cardCount: existing.cards.count, trashed: existing.trashedAt != nil)
        }
        let deck = StudyDeck(title: "Mazo de prueba · Repaso general", id: id, now: now)
        let examples = [
            ("¿Qué es una célula?", "La unidad básica estructural y funcional de los seres vivos."),
            ("¿Cuál es la función principal de las mitocondrias?", "Producir ATP mediante la respiración celular."),
            ("¿Qué es la fotosíntesis?", "El proceso que transforma energía luminosa en energía química almacenada en moléculas orgánicas."),
            ("¿Cuál es la derivada de x² respecto de x?", "2x."),
            ("¿Qué establece el teorema de Pitágoras?", "En un triángulo rectángulo, a² + b² = c², donde c es la hipotenusa."),
            ("¿Cuál es la fórmula del área de un círculo?", "A = πr², donde r es el radio."),
            ("¿En qué año comenzó la Revolución francesa?", "En 1789."),
            ("¿Qué significa recuperar activamente información al estudiar?", "Intentar recordar una respuesta sin mirar los apuntes y comprobarla después.")
        ]
        context.insert(deck)
        for (question, answer) in examples {
            let card = Flashcard(question: question, answer: answer, now: now)
            context.insert(card); card.deck = deck
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
        return Result(id: deck.id, cardCount: deck.cards.count, trashed: false)
    }

    /// A small non-content receipt lets the device operation be verified without copying the library.
    static func createIfRequested(in container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("--create-study-sample-deck") else { return }
        do {
            let deck = try create(in: container)
            let receipt: [String: Any] = ["deckID": deck.id.uuidString, "cardCount": deck.cardCount,
                                          "trashed": deck.trashed, "verifiedAt": Date.now.timeIntervalSince1970]
            let url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
                .appendingPathComponent("StudySampleReceipt.json")
            try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Study sample creation failed: \(error.localizedDescription)\n".utf8))
        }
    }
}
