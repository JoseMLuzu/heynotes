import XCTest
import SwiftUI
import SwiftData
import PencilKit
@testable import NotesApp

@MainActor final class PersonalizationTests: XCTestCase {
    private var containers: [ModelContainer] = []
    func testEverySampleAccentHasReadableLightAndDarkForegrounds() throws {
        let light = ThemeColorValue(red: 0.925, green: 0.93, blue: 0.91)
        let dark = ThemeColorValue(red: 0.09, green: 0.10, blue: 0.095)
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let samples = [0.0, 0.25, 0.5, 0.75, 1.0]
        for red in samples { for green in samples { for blue in samples {
            let palette = AccentPalette(.init(red: red, green: green, blue: blue))
            XCTAssertGreaterThanOrEqual(contrast(palette.light, light), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(palette.light, light.mixed(with: palette.light, amount: 0.12)), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(palette.dark, dark.mixed(with: palette.dark, amount: 0.12)), 4.5)
            let header = UIColor(palette.headerBackground)
            let lightHeader = try XCTUnwrap(ThemeColorValue(header.resolvedColor(with: lightTraits)))
            let darkHeader = try XCTUnwrap(ThemeColorValue(header.resolvedColor(with: darkTraits)))
            XCTAssertGreaterThanOrEqual(contrast(palette.light, lightHeader), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(palette.dark, darkHeader), 4.5)
            XCTAssertLessThanOrEqual(palette.highLight.luminance, palette.light.luminance)
            XCTAssertGreaterThanOrEqual(palette.highDark.luminance, palette.dark.luminance)
        } } }
    }

    func testSettingsPersistAndInvalidPreferencesUseSafeDefaults() throws {
        let name = "AppSettings.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = AppPreferences(defaults: defaults)
        prefs.accent = .init(red: 1, green: 0.9, blue: 0)
        prefs.appearance = .dark; prefs.defaultPaper = .grid
        let reopened = AppPreferences(defaults: defaults)
        XCTAssertEqual(reopened.accent, prefs.accent); XCTAssertEqual(reopened.appearance, .dark)
        XCTAssertEqual(reopened.defaultPaper, .grid)
        reopened.resetAppearance()
        XCTAssertEqual(reopened.accent, FolderColor.sage.value); XCTAssertEqual(reopened.appearance, .system)
        XCTAssertEqual(reopened.defaultPaper, .grid)
        defaults.set(Data([0, 1, 2]), forKey: "app.accent.v1")
        defaults.set("future", forKey: "app.appearance.v1")
        defaults.set("unknown-paper", forKey: "app.defaultPaper.v1")
        let recovered = AppPreferences(defaults: defaults)
        XCTAssertEqual(recovered.accent, FolderColor.sage.value); XCTAssertEqual(recovered.appearance, .system)
        XCTAssertEqual(recovered.defaultPaper, .blank)
    }

    func testV4FolderMigrationPreservesActualEditableInkOnIPad() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store"), id = UUID(), pageID = UUID()
        let ink = drawing(), bytes = ink.dataRepresentation()
        try bytes.write(to: root.appendingPathComponent("kept.drawing"))
        do {
            let schema = Schema(versionedSchema: NotesSchemaV4.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let folder = NotesSchemaV4.Folder(title: "Biology", id: id)
            let book = NotesSchemaV4.Notebook(title: "Existing", folder: folder)
            let page = NotesSchemaV4.NotePage(pageIndex: 0, id: pageID); page.drawingFilePath = "kept.drawing"
            old.mainContext.insert(folder); old.mainContext.insert(book); old.mainContext.insert(page)
            book.pages = [page]; try old.mainContext.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url); containers.append(migrated)
        let folder = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Folder>()).first)
        XCTAssertEqual(folder.id, id); XCTAssertEqual(folder.color, .sage)
        XCTAssertEqual(folder.notebooks.first?.pages.first?.id, pageID)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("kept.drawing")), bytes)
        XCTAssertEqual(try PKDrawing(data: Data(contentsOf: root.appendingPathComponent("kept.drawing"))), ink)
    }

    func testChangingAppAccentDoesNotReplaceCanvasInkOrEditNotebook() async throws {
        let prefs = AppPreferences.shared, previous = prefs.accent
        defer { prefs.accent = previous }
        let container = try PersistenceController.makeContainer(inMemory: true); containers.append(container)
        let notebook = Notebook(title: "Accent"), page = NotePage(pageIndex: 0)
        container.mainContext.insert(notebook); container.mainContext.insert(page); notebook.pages = [page]
        let session = EditorSession(notebook: notebook, context: container.mainContext)
        await session.open(page); session.drawing = drawing()
        let updatedAt = notebook.updatedAt
        let (window, host) = try host(EditorView(session: session, onLibrary: {}).modifier(AppAppearance()))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(host)
        let canvas = try XCTUnwrap(session.canvas), original = canvas.drawing
        let inkTool = try XCTUnwrap(canvas.tool as? PKInkingTool)
        for (name, value) in [("Lavender", FolderColor.lavender.value), ("Custom-Yellow", .init(red: 1, green: 1, blue: 0))] {
            prefs.accent = value
            try await settle(host)
            XCTAssertTrue(session.canvas === canvas); XCTAssertEqual(canvas.drawing, original)
            XCTAssertEqual((canvas.tool as? PKInkingTool)?.color, inkTool.color)
            XCTAssertEqual(notebook.updatedAt, updatedAt)
            capture(host, name: "Editor-Header-\(name)")
        }
    }

    func testSettingsAndRealFolderLibraryAppearance() async throws {
        let prefs = AppPreferences.shared, oldAccent = prefs.accent, oldAppearance = prefs.appearance
        defer { prefs.accent = oldAccent; prefs.appearance = oldAppearance }
        let container = try PersistenceController.makeContainer(inMemory: true); containers.append(container)
        for color in FolderColor.allCases {
            let folder = Folder(title: color.title); folder.color = color; container.mainContext.insert(folder)
        }
        try container.mainContext.save()
        for appearance in [AppPreferences.Appearance.light, .dark] {
            prefs.appearance = appearance; prefs.accent = FolderColor.lavender.value
            let (window, host) = try host(AppSettingsView(), size: CGSize(width: 820, height: 1180))
            window.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
            try await settle(host); capture(host, name: "Settings-\(appearance.rawValue)")
            window.isHidden = true; window.rootViewController = nil
        }
        prefs.appearance = .light
        let (window, host) = try host(LibraryView(context: container.mainContext).modelContainer(container).modifier(AppAppearance()),
                                      size: CGSize(width: 1366, height: 1024))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(host)
        let split = try XCTUnwrap(controllers(host).compactMap { $0 as? UISplitViewController }.first)
        split.show(.primary)
        try await Task.sleep(for: .milliseconds(400))
        try await settle(host)
        capture(host, name: "Folder-Colors-Library-Sidebar")
    }

    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 80, y: 100), CGPoint(x: 260, y: 180)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }
    private func contrast(_ a: ThemeColorValue, _ b: ThemeColorValue) -> Double {
        (max(a.luminance, b.luminance) + 0.05) / (min(a.luminance, b.luminance) + 0.05)
    }
    private func controllers(_ controller: UIViewController) -> [UIViewController] {
        [controller] + controller.children.flatMap(controllers)
    }
    private func host<Content: View>(_ content: Content, size: CGSize = CGSize(width: 1180, height: 820)) throws -> (UIWindow, UIHostingController<Content>) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content); window.rootViewController = host; window.isHidden = false
        host.view.frame = window.bounds; host.view.layoutIfNeeded(); return (window, host)
    }
    private func settle<Content: View>(_ host: UIHostingController<Content>) async throws {
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(150)); host.view.layoutIfNeeded()
    }
    private func capture<Content: View>(_ host: UIHostingController<Content>, name: String) {
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
