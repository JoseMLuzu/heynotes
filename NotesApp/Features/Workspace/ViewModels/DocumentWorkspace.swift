import Foundation
import Observation
import SwiftData

/// One active editor, lightweight document tabs, and a small local navigation history.
@MainActor @Observable
final class DocumentWorkspace {
    private struct Saved: Codable, Equatable {
        var openIDs: [UUID] = []
        var recentIDs: [UUID] = []
        var activeID: UUID?
        var pages: [UUID: UUID] = [:]
    }
    private(set) var openNotebooks: [Notebook] = []
    private(set) var recentNotebooks: [Notebook] = []
    private(set) var activeSession: EditorSession?
    private(set) var isSwitching = false
    var errorMessage: String?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let storage: DrawingStorage
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saved: Saved
    @ObservationIgnored private var lastPersisted: Saved?
    @ObservationIgnored private var restored = false
    private static let key = "workspace.tabs.v1"

    init(context: ModelContext, storage: DrawingStorage = .shared, defaults: UserDefaults = .standard) {
        self.context = context; self.storage = storage; self.defaults = defaults
        let restored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        saved = restored ?? Saved(); lastPersisted = restored
    }

    var activeID: UUID? { activeSession?.notebook.id }
    // Only observable operation state gates the tab strip. UIKit gesture state is
    // checked at navigation activation, never cached as a SwiftUI hit-test flag.
    var blocksTabControls: Bool { isSwitching || activeSession?.busy == true }
    var blocksNavigation: Bool {
        let stroke = activeSession?.canvas?.drawingGestureRecognizer.state
        return isSwitching || activeSession?.busy == true || stroke == .began || stroke == .changed
    }

    func restore() async {
        guard !restored else { return }
        restored = true; isSwitching = true
        defer { isSwitching = false }
        do {
            let notebooks = try context.fetch(FetchDescriptor<Notebook>())
            let lookup = Dictionary(uniqueKeysWithValues: notebooks.filter { !$0.isInTrash }.map { ($0.id, $0) })
            openNotebooks = unique(saved.openIDs).compactMap { lookup[$0] }
            recentNotebooks = Array(unique(saved.recentIDs).compactMap { lookup[$0] }.prefix(20))
            if let id = saved.activeID, let notebook = openNotebooks.first(where: { $0.id == id }) {
                await activate(notebook)
            }
            persist()
        } catch {
            errorMessage = "Open tabs could not be restored. Your notebooks are unchanged. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func open(_ notebook: Notebook) async -> Bool {
        guard !blocksNavigation else { return false }
        guard !notebook.isInTrash else { errorMessage = "Restore this notebook from Trash before opening it."; return false }
        if activeID == notebook.id { return true }
        guard !notebook.pages.isEmpty else {
            errorMessage = "This notebook has no available pages. Your saved files have not been removed."
            return false
        }
        isSwitching = true
        defer { isSwitching = false }
        guard await saveCurrent() else { return false }
        if !openNotebooks.contains(where: { $0.id == notebook.id }) { openNotebooks.append(notebook) }
        await activate(notebook)
        persist()
        return true
    }

    @discardableResult
    func showLibrary() async -> Bool {
        guard !blocksNavigation else { return false }
        isSwitching = true
        defer { isSwitching = false }
        guard await saveCurrent() else { return false }
        releaseCanvas()
        activeSession = nil
        persist()
        return true
    }

    @discardableResult
    func close(_ id: UUID) async -> Bool {
        guard !blocksNavigation else { return false }
        guard let index = openNotebooks.firstIndex(where: { $0.id == id }) else { return true }
        isSwitching = true
        defer { isSwitching = false }
        if activeID == id {
            guard await saveCurrent() else { return false }
            releaseCanvas()
            activeSession = nil
            openNotebooks.remove(at: index)
            if !openNotebooks.isEmpty {
                await activate(openNotebooks[min(index, openNotebooks.count - 1)])
            }
        } else { openNotebooks.remove(at: index) }
        persist()
        return true
    }

    /// Called before metadata deletion so tab views never retain a deleted SwiftData object.
    func forget(_ id: UUID) async -> Bool {
        guard await close(id) else { return false }
        recentNotebooks.removeAll { $0.id == id }
        saved.pages.removeValue(forKey: id)
        persist()
        return true
    }

    /// Remove a whole folder's tab references with one save boundary and no intermediate loads.
    func forget(_ ids: Set<UUID>) async -> Bool {
        guard !blocksNavigation else { return false }
        isSwitching = true
        defer { isSwitching = false }
        if let id = activeID, ids.contains(id) {
            guard await saveCurrent() else { return false }
            releaseCanvas(); activeSession = nil
        }
        openNotebooks.removeAll { ids.contains($0.id) }
        recentNotebooks.removeAll { ids.contains($0.id) }
        for id in ids { saved.pages.removeValue(forKey: id) }
        persist()
        return true
    }

    func rememberCurrentPage() {
        if let session = activeSession, let page = session.page { saved.pages[session.notebook.id] = page.id }
        persist()
    }

    func backgroundSave() {
        rememberCurrentPage()
        activeSession?.backgroundSave()
    }

    private func saveCurrent() async -> Bool {
        guard let session = activeSession else { return true }
        session.handwriting.cancel()
        guard await session.flush() else { return false }
        if let page = session.page { saved.pages[session.notebook.id] = page.id }
        return true
    }

    private func activate(_ notebook: Notebook) async {
        let remembered = saved.pages[notebook.id].flatMap { id in notebook.pages.first { $0.id == id } }
        guard let destination = remembered ?? notebook.pages.min(by: {
            $0.pageIndex == $1.pageIndex ? $0.id.uuidString < $1.id.uuidString : $0.pageIndex < $1.pageIndex
        }) else { return }
        let incoming = EditorSession(notebook: notebook, context: context, storage: storage)
        // Keep the outgoing editor visible until the next document has loaded.
        await incoming.open(destination)
        releaseCanvas()
        activeSession = incoming
        recentNotebooks.removeAll { $0.id == notebook.id }
        recentNotebooks.insert(notebook, at: 0)
        recentNotebooks = Array(recentNotebooks.prefix(20))
    }

    private func releaseCanvas() {
        activeSession?.handwriting.cancel()
        activeSession?.canvas?.delegate = nil
        activeSession?.canvas = nil
    }

    private func persist() {
        saved.openIDs = openNotebooks.map(\.id)
        saved.recentIDs = recentNotebooks.map(\.id)
        saved.activeID = activeID
        if let session = activeSession, let page = session.page { saved.pages[session.notebook.id] = page.id }
        let retained = Set(saved.openIDs + saved.recentIDs)
        saved.pages = saved.pages.filter { retained.contains($0.key) }
        guard saved != lastPersisted else { return }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.key)
            lastPersisted = saved
        }
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
