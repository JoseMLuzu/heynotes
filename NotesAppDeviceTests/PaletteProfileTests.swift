import XCTest
import PencilKit
@testable import NotesApp

@MainActor final class PaletteProfileTests: XCTestCase {
    private struct LegacyFixture: Codable {
        var favorites: [ToolPreset]
        var position: PalettePosition
        var collapsed: Bool
        var visible: Bool
    }

    func testLegacyFavoritesMigrateWithoutLosingIDsOrPresentationState() throws {
        let suite = "PaletteProfilesMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let favorite = ToolPreset(name: "Existing pen", tool: .pen, ink: InkStyle(red: 0.4, green: 0.1, blue: 0.7, width: 4, opacity: 0.75))
        let legacy = LegacyFixture(favorites: [favorite], position: PalettePosition(x: 0.7, y: 0.3), collapsed: true, visible: false)
        let originalData = try JSONEncoder().encode(legacy)
        defaults.set(originalData, forKey: "editor.quickPalette.v1")
        let palette = QuickPalettePreferences(defaults: defaults)
        XCTAssertEqual(palette.profiles.count, 1)
        XCTAssertEqual(palette.activeProfile.name, "My Palette")
        XCTAssertEqual(palette.favorites, [favorite])
        XCTAssertEqual(palette.position, legacy.position)
        XCTAssertTrue(palette.isCollapsed); XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(defaults.data(forKey: "editor.quickPalette.v1"), originalData)
        XCTAssertNotNil(defaults.data(forKey: "editor.quickPalette.v2"))
        let id = palette.activeProfile.id
        var changed = favorite; changed.name = "After migration"
        XCTAssertTrue(palette.save(changed))
        let reopened = QuickPalettePreferences(defaults: defaults)
        XCTAssertEqual(reopened.activeProfile.id, id)
        XCTAssertEqual(reopened.favorites.first?.name, "After migration") // v2 takes precedence over retained v1.
        XCTAssertEqual(defaults.data(forKey: "editor.quickPalette.v1"), originalData)
    }

    func testIndependentProfilesDuplicateRenameDeleteAndReopen() throws {
        let suite = "PaletteProfilesCRUD.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = QuickPalettePreferences(defaults: defaults)
        let original = palette.activeProfile
        XCTAssertFalse(palette.deleteProfile(original.id))
        XCTAssertFalse(palette.createProfile(name: "   ", initialTool: original.favorites[0]))
        XCTAssertTrue(palette.duplicateProfile(original.id, name: "Study"))
        let study = palette.activeProfile
        XCTAssertNotEqual(study.id, original.id)
        XCTAssertEqual(study.favorites.map(\.ink), original.favorites.map(\.ink))
        XCTAssertTrue(Set(study.favorites.map(\.id)).isDisjoint(with: original.favorites.map(\.id)))
        var first = study.favorites[0]; first.name = "Purple notes"; first.ink.red = 0.7
        XCTAssertTrue(palette.save(first))
        XCTAssertTrue(palette.selectProfile(original.id))
        XCTAssertEqual(palette.activeProfile, original)
        XCTAssertFalse(palette.renameProfile(original.id, name: "study"))
        XCTAssertTrue(palette.renameProfile(original.id, name: "Class"))
        let selectedTool = ToolPreferences(defaults: defaults)
        selectedTool.apply(first)
        let beforeSwitch = selectedTool.capturePreset()
        XCTAssertTrue(palette.selectProfile(study.id))
        XCTAssertEqual(selectedTool.ink, beforeSwitch.ink)
        XCTAssertTrue(palette.renameProfile(study.id, name: "Review"))
        XCTAssertTrue(palette.createProfile(name: "PDF", initialTool: ToolPreset(name: "Highlight", tool: .marker,
            ink: InkStyle(red: 1, green: 0.8, blue: 0.1, width: 18, opacity: 0.5))))
        let pdfID = palette.activeProfile.id
        XCTAssertEqual(palette.favorites.count, 1)
        let reopened = QuickPalettePreferences(defaults: defaults)
        XCTAssertEqual(reopened.activeProfile.id, pdfID)
        XCTAssertEqual(reopened.profiles.map(\.name), ["Class", "Review", "PDF"])
        XCTAssertTrue(reopened.deleteProfile(pdfID))
        XCTAssertEqual(reopened.activeProfile.id, study.id)
        XCTAssertTrue(reopened.deleteProfile(original.id))
        XCTAssertFalse(reopened.deleteProfile(study.id))
        XCTAssertEqual(QuickPalettePreferences(defaults: defaults).activeProfile.name, "Review")
    }

    func testFavoriteDraftTargetsOriginalProfileAndDeletedProfileIsRejected() throws {
        let suite = "PaletteProfileDraft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = QuickPalettePreferences(defaults: defaults)
        let originalID = palette.activeProfile.id
        var draft = try XCTUnwrap(palette.favorites.first)
        draft.name = "Original profile edit"
        XCTAssertTrue(palette.createProfile(name: "PDF", initialTool: ToolPreset(name: "Lasso", tool: .lasso)))
        let pdf = palette.activeProfile
        XCTAssertTrue(palette.save(draft, in: originalID))
        XCTAssertEqual(palette.activeProfile, pdf)
        XCTAssertEqual(palette.profiles.first { $0.id == originalID }?.favorites.first?.name, draft.name)
        XCTAssertTrue(palette.deleteProfile(originalID))
        XCTAssertFalse(palette.save(draft, in: originalID))
        XCTAssertEqual(palette.activeProfile, pdf)
        XCTAssertFalse(palette.selectProfile(UUID()))
    }
}
