import XCTest
import SwiftUI
import SwiftData
import PencilKit
import UniformTypeIdentifiers
@testable import NotesApp

@MainActor final class PaletteToolDragTests: XCTestCase {
    func testToolbarDragCapturesInactiveToolWithoutSelectingItAndRevealsPalette() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        f.tools.selected = .marker
        f.tools.ink = InkStyle(red: 0.1, green: 0.8, blue: 0.3, width: 25, opacity: 0.4)
        let marker = f.tools.ink
        f.tools.selected = .pen; f.tools.ink.width = 4
        f.tools.eraserMode = .precise; f.tools.eraserWidth = 35
        f.palette.isVisible = false; f.palette.isCollapsed = true
        let before = f.defaults.data(forKey: "editor.tools.v1")
        let favorites = f.palette.favorites
        let source = PaletteToolDragSource(snapshot: { f.tools.capturePreset(for: .marker) }, palette: f.palette, canInteract: { true })
        let provider = source.provider()
        let data = try await bytes(provider)
        let value = try PaletteToolDrag.decode(data)
        XCTAssertEqual(value.preset.tool, .marker); XCTAssertEqual(value.preset.ink, marker)
        XCTAssertEqual(f.tools.selected, .pen); XCTAssertEqual(f.defaults.data(forKey: "editor.tools.v1"), before)
        XCTAssertTrue(f.palette.isVisible); XCTAssertFalse(f.palette.isCollapsed)
        XCTAssertEqual(f.palette.favorites, favorites) // Cancelling the drag has not added a favorite.
        f.tools.selected = .marker; f.tools.ink.width = 30
        let capturedAgain = try await bytes(provider)
        XCTAssertEqual(try PaletteToolDrag.decode(capturedAgain).preset.ink, marker)
        let eraser = f.tools.capturePreset(for: .eraser)
        XCTAssertEqual(eraser.eraserMode, .precise); XCTAssertEqual(eraser.eraserWidth, 35)
        XCTAssertEqual(f.tools.selected, .marker)
        f.palette.isVisible = false
        let blocked = PaletteToolDragSource(snapshot: { eraser }, palette: f.palette, canInteract: { false }).provider()
        XCTAssertFalse(blocked.hasItemConformingToTypeIdentifier(UTType.paletteTool.identifier))
        XCTAssertFalse(f.palette.isVisible)
    }

    func testNativeProviderDropReplacesTargetAndAppendsOnlyOnEmptySpace() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        let old = f.palette.favorites, oldProfile = f.palette.activeProfile.id
        let snapshot = f.tools.capturePreset(for: .pencil)
        let drag = PaletteToolDrag(preset: snapshot)
        var completed = false
        let receiver = PaletteDropReceiver(palette: f.palette, profileID: oldProfile, canInteract: { true }) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); completed = true
        }
        XCTAssertTrue(receiver.receive([drag.itemProvider()], onto: old[1].id))
        try await waitUntil { completed }
        XCTAssertEqual(f.palette.favorites.count, old.count)
        let replaced = f.palette.favorites[1]
        XCTAssertEqual(replaced.id, old[1].id); XCTAssertNotEqual(replaced.id, snapshot.id)
        XCTAssertEqual(replaced.ink, snapshot.ink); XCTAssertEqual(replaced.tool, .pencil)
        XCTAssertEqual(f.palette.favorites.map(\.id), old.map(\.id))
        XCTAssertEqual(f.palette.favorites.filter { $0.id != replaced.id }, old.filter { $0.id != replaced.id })
        let reopened = QuickPalettePreferences(defaults: f.defaults)
        XCTAssertEqual(reopened.favorites, f.palette.favorites)
        XCTAssertTrue(f.palette.acceptDrop(drag, onto: nil, in: oldProfile))
        XCTAssertEqual(f.palette.favorites.count, 6)
        XCTAssertNotEqual(f.palette.favorites.last?.id, snapshot.id)
        let full = f.palette.profiles
        XCTAssertFalse(f.palette.acceptDrop(drag, onto: nil, in: oldProfile))
        XCTAssertEqual(f.palette.profiles, full)
    }

    func testReplacementWorksAtCapacityWithoutChangingOtherSlotsProfilesOrActiveTool() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        XCTAssertTrue(f.palette.save(ToolPreset(name: "Selection", tool: .lasso)))
        let profileID = f.palette.activeProfile.id
        XCTAssertTrue(f.palette.duplicateProfile(profileID, name: "Other profile"))
        let other = f.palette.activeProfile
        XCTAssertTrue(f.palette.selectProfile(profileID))
        let original = f.palette.favorites
        let toolBytes = f.defaults.data(forKey: "editor.tools.v1")
        let snapshot = ToolPreset(name: "Green marker", tool: .marker,
            ink: InkStyle(red: 0.1, green: 0.7, blue: 0.3, width: 24, opacity: 0.45))
        var completed = false
        let receiver = PaletteDropReceiver(palette: f.palette, profileID: profileID, canInteract: { true }) { success, message in
            XCTAssertTrue(success); XCTAssertNil(message); completed = true
        }
        XCTAssertTrue(receiver.receive([PaletteToolDrag(preset: snapshot).itemProvider()], onto: original[2].id))
        try await waitUntil { completed }
        XCTAssertEqual(f.palette.favorites.count, 6)
        XCTAssertEqual(f.palette.favorites.map(\.id), original.map(\.id))
        var expected = snapshot.sanitized; expected.id = original[2].id
        XCTAssertEqual(f.palette.favorites[2], expected)
        XCTAssertEqual(f.palette.favorites.filter { $0.id != expected.id }, original.filter { $0.id != expected.id })
        XCTAssertEqual(f.palette.profiles.first { $0.id == other.id }, other)
        XCTAssertEqual(f.defaults.data(forKey: "editor.tools.v1"), toolBytes)
        XCTAssertEqual(QuickPalettePreferences(defaults: f.defaults).favorites, f.palette.favorites)
        // Render the actual hover styling for visual QA without simulating private drag events.
        let preview = HStack(spacing: 12) {
            PaletteFavoriteIcon(favorite: original[2], selected: false)
            PaletteFavoriteIcon(favorite: original[2], selected: false, dropTargeted: true)
        }.padding(20).background(.white).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: preview); renderer.scale = 2
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "Palette-Replacement-Hover"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testLateDropDoesNotReplaceADeletedTargetOrAppendIntoItsOldPosition() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        XCTAssertTrue(f.palette.save(ToolPreset(name: "Selection", tool: .lasso)))
        let id = f.palette.activeProfile.id, target = f.palette.favorites[1].id
        var completed = false
        let receiver = PaletteDropReceiver(palette: f.palette, profileID: id, canInteract: { true }) { success, message in
            XCTAssertFalse(success); XCTAssertEqual(message, "The favorite changed. Drop the tool again."); completed = true
        }
        let drag = PaletteToolDrag(preset: ToolPreset(name: "Incoming", tool: .eraser, eraserMode: .highlighter, eraserWidth: 50))
        XCTAssertTrue(receiver.receive([drag.itemProvider()], onto: target))
        f.palette.remove(target)
        XCTAssertTrue(f.palette.save(ToolPreset(name: "New slot", tool: .laser)))
        let unchanged = f.palette.profiles
        try await waitUntil { completed }
        XCTAssertEqual(f.palette.profiles, unchanged)
    }

    func testFavoriteReorderWorksAtCapacityRetainsIDsAndDoesNotChangeOtherProfilesOrTools() throws {
        let f = try DragFixture(); defer { f.cleanup() }
        let original = f.palette.activeProfile
        XCTAssertTrue(f.palette.duplicateProfile(original.id, name: "Study"))
        let id = f.palette.activeProfile.id
        XCTAssertTrue(f.palette.save(f.tools.capturePreset(for: .lasso)))
        let initial = f.palette.favorites
        let toolBefore = f.defaults.data(forKey: "editor.tools.v1")
        let source = PaletteToolDrag(preset: initial[0], paletteID: f.palette.dragScopeID, profileID: id)
        XCTAssertTrue(f.palette.acceptDrop(source, onto: initial[2].id, in: id))
        XCTAssertEqual(Array(f.palette.favorites.prefix(3)).map(\.id), [initial[1].id, initial[2].id, initial[0].id])
        XCTAssertTrue(f.palette.acceptDrop(source, onto: nil, in: id))
        XCTAssertEqual(f.palette.favorites.last?.id, initial[0].id)
        XCTAssertEqual(Set(f.palette.favorites.map(\.id)), Set(initial.map(\.id)))
        XCTAssertEqual(f.palette.profiles.first { $0.id == original.id }, original)
        XCTAssertEqual(f.defaults.data(forKey: "editor.tools.v1"), toolBefore)
        XCTAssertEqual(QuickPalettePreferences(defaults: f.defaults).favorites, f.palette.favorites)
        let unchanged = f.palette.profiles
        XCTAssertFalse(f.palette.acceptDrop(source, onto: UUID(), in: id))
        XCTAssertEqual(f.palette.profiles, unchanged)
    }

    func testCrossProfileAndCrossPaneDragsCopyAndLateDropsRejectChangedDestination() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        let original = f.palette.activeProfile
        let favorite = original.favorites[0]
        let source = PaletteToolDrag(preset: favorite, paletteID: f.palette.dragScopeID, profileID: original.id)
        XCTAssertTrue(f.palette.createProfile(name: "PDF", initialTool: f.tools.capturePreset(for: .marker)))
        let destination = f.palette.activeProfile.id
        XCTAssertTrue(f.palette.acceptDrop(source, onto: nil, in: destination))
        XCTAssertNotEqual(f.palette.favorites.last?.id, favorite.id)
        XCTAssertEqual(f.palette.profiles.first { $0.id == original.id }, original)
        let targetID = f.palette.favorites[0].id, count = f.palette.favorites.count
        XCTAssertTrue(f.palette.acceptDrop(source, onto: targetID, in: destination))
        XCTAssertEqual(f.palette.favorites.count, count); XCTAssertEqual(f.palette.favorites[0].id, targetID)
        XCTAssertEqual(f.palette.favorites[0].ink, favorite.ink)
        XCTAssertEqual(f.palette.profiles.first { $0.id == original.id }, original)
        // Another pane may have the same persisted profile IDs but a different preference owner.
        let otherPane = QuickPalettePreferences(defaults: f.defaults)
        let before = otherPane.favorites
        let incoming = PaletteToolDrag(preset: before[0], paletteID: f.palette.dragScopeID, profileID: destination)
        XCTAssertTrue(otherPane.acceptDrop(incoming, onto: nil, in: destination))
        XCTAssertEqual(otherPane.favorites.count, before.count + 1)
        XCTAssertNotEqual(otherPane.favorites.last?.id, before[0].id)
        var finished = false
        let receiver = PaletteDropReceiver(palette: f.palette, profileID: destination, canInteract: { true }) { success, message in
            XCTAssertFalse(success); XCTAssertNotNil(message); finished = true
        }
        XCTAssertTrue(receiver.receive([source.itemProvider()], onto: nil))
        XCTAssertTrue(f.palette.selectProfile(original.id)) // Happens before asynchronous delivery returns to MainActor.
        let unchanged = f.palette.profiles
        try await waitUntil { finished }
        XCTAssertEqual(f.palette.profiles, unchanged)
    }

    func testInvalidMultiItemAndBusyDropsDoNotModifyPreferences() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        let id = f.palette.activeProfile.id, before = f.palette.profiles
        let source = PaletteToolDrag(preset: f.tools.capturePreset())
        let blocked = PaletteDropReceiver(palette: f.palette, profileID: id, canInteract: { false }) { _, _ in XCTFail() }
        XCTAssertFalse(blocked.receive([source.itemProvider()], onto: nil))
        let receiver = PaletteDropReceiver(palette: f.palette, profileID: id, canInteract: { true }) { success, message in
            XCTAssertFalse(success); XCTAssertNotNil(message)
        }
        XCTAssertFalse(receiver.receive([source.itemProvider(), source.itemProvider()], onto: nil))
        XCTAssertFalse(receiver.receive([NSItemProvider(object: "text" as NSString)], onto: nil))
        var future = source; future.version = 2
        XCTAssertThrowsError(try PaletteToolDrag.decode(JSONEncoder().encode(future)))
        XCTAssertThrowsError(try PaletteToolDrag.decode(Data(repeating: 0, count: 16_385)))
        XCTAssertThrowsError(try PaletteToolDrag.decode(Data([0, 1, 2])))
        var finished = false
        let rejecting = PaletteDropReceiver(palette: f.palette, profileID: id, canInteract: { true }) { success, message in
            XCTAssertFalse(success); XCTAssertNotNil(message); finished = true
        }
        XCTAssertTrue(rejecting.receive([future.itemProvider()], onto: nil))
        try await waitUntil { finished }
        XCTAssertEqual(f.palette.profiles, before)
        f.palette.isVisible = false
        let favoriteSource = PaletteToolDragSource(snapshot: { f.palette.favorites[0] }, palette: f.palette,
                                                   fromFavorite: true, canInteract: { true })
        _ = favoriteSource.provider()
        XCTAssertFalse(f.palette.isVisible, "Focus Mode favorite drags must not rewrite hidden palette presentation")
    }

    func testNativeEditorKeepsCanvasAndIndividualTargetsAtEveryToolbarEdge() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        let container = try PersistenceController.makeContainer(inMemory: true), book = Notebook(title: "Drag tools")
        let page = NotePage(pageIndex: 0)
        container.mainContext.insert(book); container.mainContext.insert(page); book.pages = [page]; try container.mainContext.save()
        let session = EditorSession(notebook: book, context: container.mainContext)
        await session.open(page); defer { session.discardPreparedPages() }
        let controls = EditorControlPreferences(defaults: f.defaults, palette: f.palette)
        let placement = EditorToolbarPreferences(defaults: f.defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(rootView: EditorView(session: session, onLibrary: {}, toolbarPlacement: placement,
                                                           controls: controls).preferredColorScheme(.light))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        try await settle(host.view)
        let canvas = try XCTUnwrap(session.canvas)
        for edge in EditorToolbarPosition.allCases {
            placement.position = edge; try await settle(host.view)
            XCTAssertTrue(session.canvas === canvas)
            let interactions = descendants(host.view).flatMap(\.interactions)
            XCTAssertTrue(interactions.contains { $0 is UIDragInteraction }, "Native drag source missing at \(edge)")
            XCTAssertTrue(interactions.contains { $0 is UIDropInteraction }, "Native drop destination missing at \(edge)")
        }
        let before = page.updatedAt
        XCTAssertTrue(f.palette.acceptDrop(PaletteToolDrag(preset: controls.tools.capturePreset(for: .marker)), onto: nil,
                                          in: f.palette.activeProfile.id))
        try await settle(host.view)
        XCTAssertTrue(session.canvas === canvas); XCTAssertEqual(page.updatedAt, before)
        XCTAssertFalse(session.hasPendingSave)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Palette-Drag-Six-Favorites"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testEachNativeDropDelegateReplacesItsOwnFavoriteAtCapacity() async throws {
        let f = try DragFixture(); defer { f.cleanup() }
        XCTAssertTrue(f.palette.save(ToolPreset(name: "Sixth", tool: .lasso)))
        let original = f.palette.favorites
        let profile = f.palette.activeProfile.id
        for (index, target) in original.enumerated() {
            let preset = ToolPreset(name: "Replacement \(index)", tool: .marker,
                ink: InkStyle(red: Double(index) / 6, green: 0.3, blue: 0.8, width: 18))
            let before = f.palette.favorites
            var completed = false
            let delegate = PaletteToolDrop(palette: f.palette, profileID: profile, favoriteID: target.id,
                canInteract: { true }, hovering: { _, _ in }, completed: { success, message in
                    XCTAssertTrue(success); XCTAssertNil(message); completed = true
                })
            XCTAssertTrue(delegate.receive([PaletteToolDrag(preset: preset).itemProvider()]))
            try await waitUntil { completed }
            XCTAssertEqual(f.palette.favorites.count, 6)
            XCTAssertEqual(f.palette.favorites[index].id, target.id)
            XCTAssertEqual(f.palette.favorites[index].name, preset.name)
            XCTAssertEqual(f.palette.favorites.filter { $0.id != target.id }, before.filter { $0.id != target.id })
        }
    }

    private func bytes(_ provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.paletteTool.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.coderReadCorrupt)) }
            }
        }
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Native item provider did not finish")
    }
    private func settle(_ view: UIView) async throws { view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(100)); view.layoutIfNeeded() }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

@MainActor private final class DragFixture {
    let suite = "PaletteToolDrag.\(UUID())"
    let defaults: UserDefaults
    let tools: ToolPreferences
    let palette: QuickPalettePreferences
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        tools = ToolPreferences(defaults: defaults); palette = QuickPalettePreferences(defaults: defaults)
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
}
