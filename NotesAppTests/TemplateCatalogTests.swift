import Foundation
import SwiftData
import Testing
@testable import NotesAppCore

@MainActor struct TemplateCatalogTests {
    @Test func catalogPreservesLegacyValuesAndHasNoEmptyCategories() {
        #expect(PaperTemplate(rawValue: "blank") == .blank)
        #expect(PaperTemplate(rawValue: "ruled") == .ruled)
        #expect(PaperTemplate(rawValue: "grid") == .grid)
        #expect(PaperTemplate.allCases.count == 16)
        #expect(Set(PaperTemplate.allCases.map(\.title)).count == PaperTemplate.allCases.count)
        for category in TemplateCategory.allCases { #expect(PaperTemplate.allCases.contains { $0.category == category }) }
    }

    @Test func templateSelectionSurvivesReopeningWithoutChangingPageIdentity() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        var pageID: UUID?
        do {
            let container = try PersistenceController.makeContainer(storeURL: url)
            let model = LibraryViewModel(context: container.mainContext)
            #expect(model.createNotebook(title: "Cornell", color: .sage, template: .cornell, folder: nil))
            let page = try #require(model.notebooks.first?.pages.first)
            pageID = page.id; page.drawingFilePath = "ink/kept.drawing"
            page.paperTemplate = .studyPlan
            try container.mainContext.save()
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let page = try #require(reopened.mainContext.fetch(FetchDescriptor<NotePage>()).first)
        #expect(page.id == pageID)
        #expect(page.paperTemplate == .studyPlan)
        #expect(page.drawingFilePath == "ink/kept.drawing")
    }
}
