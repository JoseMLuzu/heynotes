import Foundation
import Observation
import SwiftData

/// Up to two independent live editors; tabs beyond those retain only navigation metadata.
@MainActor @Observable
final class DocumentWorkspace {
    private(set) var openNotebooks: [Notebook] = []
    private(set) var recentNotebooks: [Notebook] = []
    private(set) var primarySession: EditorSession?
    private(set) var secondarySession: EditorSession?
    private(set) var focusedPane: WorkspacePane = .primary
    private(set) var splitFraction: Double
    private(set) var panesReversed: Bool
    private(set) var isSwitching = false
    var errorMessage: String?
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let storage: DrawingStorage
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saved: WorkspaceSnapshot
    @ObservationIgnored private var lastPersisted: WorkspaceSnapshot?
    @ObservationIgnored private var restored = false
    private static let key = "workspace.tabs.v1"

    init(context: ModelContext, storage: DrawingStorage = .shared, defaults: UserDefaults = .standard) {
        self.context = context; self.storage = storage; self.defaults = defaults
        let restored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(WorkspaceSnapshot.self, from: $0) }
        saved = restored ?? WorkspaceSnapshot(); lastPersisted = restored
        splitFraction = Self.validFraction(restored?.splitFraction ?? 0.5)
        panesReversed = restored?.panesReversed ?? false
    }

    var activeSession: EditorSession? { focusedPane == .secondary ? secondarySession ?? primarySession : primarySession ?? secondarySession }
    var activeID: UUID? { activeSession?.notebook.id }
    var isSplit: Bool { primarySession != nil && secondarySession != nil }
    var visiblePanes: [WorkspacePane] {
        let panes: [WorkspacePane] = panesReversed ? [.secondary, .primary] : [.primary, .secondary]
        return panes.filter { session(in: $0) != nil }
    }
    var visibleSessions: [EditorSession] { visiblePanes.compactMap { session(in: $0) } }
    // Do not cache UIKit gesture state as a SwiftUI hit-test flag.
    var blocksTabControls: Bool { isSwitching || visibleSessions.contains { $0.busy || $0.exporting } }
    var blocksNavigation: Bool {
        blocksTabControls || visibleSessions.contains {
            let stroke = $0.canvas?.drawingGestureRecognizer.state
            return stroke == .began || stroke == .changed
        }
    }
    func contains(_ session: EditorSession) -> Bool { visibleSessions.contains { $0 === session } }

    /// Presentation-only focus: no canvas replacement or drawing save is necessary.
    func focus(_ id: UUID) {
        guard !isSwitching else { return }
        let pane: WorkspacePane
        if primarySession?.notebook.id == id { pane = .primary }
        else if secondarySession?.notebook.id == id { pane = .secondary }
        else { return }
        guard focusedPane != pane else { return }
        focusedPane = pane; persist()
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
            let firstID = saved.primaryID ?? (saved.secondaryID == nil ? saved.activeID : nil)
            if let firstID, let notebook = openNotebooks.first(where: { $0.id == firstID }) {
                primarySession = await load(notebook)
            }
            if let id = saved.secondaryID, id != primarySession?.notebook.id,
               let notebook = openNotebooks.first(where: { $0.id == id }) {
                if let first = primarySession {
                    if pairIsSafe(first.notebook, notebook) { secondarySession = await load(notebook) }
                } else { secondarySession = await load(notebook) }
            }
            focusedPane = secondarySession != nil && (secondarySession?.notebook.id == saved.activeID || primarySession == nil) ? .secondary : .primary
            persist()
        } catch { errorMessage = "Open tabs could not be restored. Your notebooks are unchanged. \(error.localizedDescription)" }
    }

    @discardableResult
    func open(_ notebook: Notebook, pageID: UUID? = nil) async -> Bool {
        guard !blocksNavigation, validate(notebook, pageID: pageID) else { return false }
        if let existing = visibleSessions.first(where: { $0.notebook.id == notebook.id }) {
            if let pageID, existing.page?.id != pageID, let target = notebook.pages.first(where: { $0.id == pageID }) {
                isSwitching = true
                await existing.open(target)
                isSwitching = false
                guard existing.page?.id == pageID else { return false }
            }
            focus(notebook.id); persist(); return true
        }
        let pane = activeSession == nil ? WorkspacePane.primary : focusedPane
        let outgoing = session(in: pane)
        if let other = session(in: pane.other), !pairIsSafe(other.notebook, notebook) { return false }
        isSwitching = true
        defer { isSwitching = false }
        guard await save(outgoing), let incoming = await load(notebook, pageID: pageID) else { return false }
        release(outgoing); assign(incoming, to: pane); focusedPane = pane
        register(notebook); persist(); return true
    }

    /// Keep the focused document and load the other file into the adjacent pane.
    @discardableResult
    func openBeside(_ notebook: Notebook) async -> Bool {
        guard !blocksNavigation, validate(notebook) else { return false }
        guard let current = activeSession else { return await open(notebook) }
        if visibleSessions.contains(where: { $0.notebook.id == notebook.id }) {
            if !isSplit { errorMessage = "Choose a different document to open beside this one."; return false }
            focus(notebook.id); return true
        }
        guard pairIsSafe(current.notebook, notebook) else { return false }
        let pane = focusedPane.other, outgoing = session(in: pane)
        isSwitching = true
        defer { isSwitching = false }
        guard await save(outgoing), let incoming = await load(notebook) else { return false }
        release(outgoing); assign(incoming, to: pane); focusedPane = pane
        register(notebook); persist(); return true
    }

    /// Retain the focused native editor, including zoom and Undo; keep the other file as a tab.
    @discardableResult
    func closeSplit() async -> Bool {
        guard !blocksNavigation else { return false }
        guard isSplit, let keep = activeSession else { return true }
        isSwitching = true
        defer { isSwitching = false }
        guard await saveAll() else { return false }
        for session in visibleSessions where session !== keep { release(session) }
        if primarySession === keep { secondarySession = nil; focusedPane = .primary }
        else { primarySession = nil; focusedPane = .secondary }
        persist(); return true
    }

    func swapPanes() {
        guard !blocksNavigation, isSplit else { return }
        panesReversed.toggle()
        splitFraction = 1 - splitFraction; persist()
    }
    func setSplitFraction(_ fraction: Double) {
        guard !blocksNavigation else { return }
        let value = Self.validFraction(fraction)
        guard value != splitFraction else { return }
        splitFraction = value; persist()
    }

    @discardableResult
    func showLibrary() async -> Bool {
        guard !blocksNavigation else { return false }
        isSwitching = true
        defer { isSwitching = false }
        guard await saveAll() else { return false }
        for session in visibleSessions { release(session) }
        primarySession = nil; secondarySession = nil; focusedPane = .primary
        persist(); return true
    }

    @discardableResult
    func close(_ id: UUID) async -> Bool {
        guard !blocksNavigation else { return false }
        guard let index = openNotebooks.firstIndex(where: { $0.id == id }) else { return true }
        isSwitching = true
        defer { isSwitching = false }
        if let closing = visibleSessions.first(where: { $0.notebook.id == id }) {
            guard await save(closing) else { return false }
            release(closing)
            if primarySession === closing { primarySession = nil } else { secondarySession = nil }
            if session(in: focusedPane) == nil { focusedPane = primarySession == nil && secondarySession != nil ? .secondary : .primary }
            openNotebooks.remove(at: index)
            if activeSession == nil, !openNotebooks.isEmpty {
                primarySession = await load(openNotebooks[min(index, openNotebooks.count - 1)])
                focusedPane = .primary
            }
        } else { openNotebooks.remove(at: index) }
        persist(); return true
    }

    func forget(_ id: UUID) async -> Bool {
        guard await close(id) else { return false }
        recentNotebooks.removeAll { $0.id == id }; saved.pages.removeValue(forKey: id)
        persist(); return true
    }

    /// Validate every pending save before changing a subtree's visible editors or tabs.
    func forget(_ ids: Set<UUID>) async -> Bool {
        guard !blocksNavigation else { return false }
        isSwitching = true
        defer { isSwitching = false }
        let removing = visibleSessions.filter { ids.contains($0.notebook.id) }
        for session in removing { guard await save(session) else { return false } }
        for session in removing { release(session) }
        if let first = primarySession, ids.contains(first.notebook.id) { primarySession = nil }
        if let second = secondarySession, ids.contains(second.notebook.id) { secondarySession = nil }
        if session(in: focusedPane) == nil { focusedPane = primarySession == nil && secondarySession != nil ? .secondary : .primary }
        openNotebooks.removeAll { ids.contains($0.id) }; recentNotebooks.removeAll { ids.contains($0.id) }
        for id in ids { saved.pages.removeValue(forKey: id) }
        persist(); return true
    }

    func rememberCurrentPage() { persist() }
    func backgroundSave() { persist(); for session in visibleSessions { session.backgroundSave() } }
    func discardPreparedPages() { for session in visibleSessions { session.discardPreparedPages() } }

    func session(in pane: WorkspacePane) -> EditorSession? { pane == .primary ? primarySession : secondarySession }
    private func assign(_ session: EditorSession, to pane: WorkspacePane) {
        if pane == .primary { primarySession = session } else { secondarySession = session }
    }
    private func saveAll() async -> Bool {
        for session in visibleSessions { guard await save(session) else { return false } }
        return true
    }
    private func save(_ session: EditorSession?) async -> Bool {
        guard let session else { return true }
        session.stopPreparingPages(); session.handwriting.cancel()
        guard await session.flush() else { return false }
        if let page = session.page { saved.pages[session.notebook.id] = page.id }
        return true
    }
    private func load(_ notebook: Notebook, pageID: UUID? = nil) async -> EditorSession? {
        let remembered = (pageID ?? saved.pages[notebook.id]).flatMap { id in notebook.pages.first { $0.id == id } }
        guard let destination = remembered ?? notebook.orderedPages.first else { return nil }
        let incoming = EditorSession(notebook: notebook, context: context, storage: storage)
        await incoming.open(destination)
        return incoming
    }
    private func release(_ session: EditorSession?) {
        session?.stopPreparingPages(); session?.handwriting.cancel()
        session?.canvas?.delegate = nil; session?.canvas = nil
    }
    private func register(_ notebook: Notebook) {
        if !openNotebooks.contains(where: { $0.id == notebook.id }) { openNotebooks.append(notebook) }
        recentNotebooks.removeAll { $0.id == notebook.id }; recentNotebooks.insert(notebook, at: 0)
        recentNotebooks = Array(recentNotebooks.prefix(20))
    }
    private func validate(_ notebook: Notebook, pageID: UUID? = nil) -> Bool {
        guard !notebook.isInTrash else { errorMessage = "Restore this notebook from Trash before opening it."; return false }
        guard !notebook.pages.isEmpty else { errorMessage = "This notebook has no available pages. Your saved files have not been removed."; return false }
        if let pageID, !notebook.pages.contains(where: { $0.id == pageID }) {
            errorMessage = "The original page is no longer available. Your study card is unchanged."; return false
        }
        return true
    }
    private func pairIsSafe(_ first: Notebook, _ second: Notebook) -> Bool {
        func canonical(_ path: String) -> String { path.split(separator: "/").filter { $0 != "." }.joined(separator: "/") }
        let paths = Set(first.pages.map { canonical($0.drawingFilePath ?? DrawingStorage.path(notebook: first.id, page: $0.id)) })
        let sharedInk = second.pages.contains { paths.contains(canonical($0.drawingFilePath ?? DrawingStorage.path(notebook: second.id, page: $0.id))) }
        guard first.id != second.id, !sharedInk else {
            errorMessage = "These documents share an editable drawing file and cannot be edited side by side safely. Open them one at a time."
            return false
        }
        return true
    }
    private func persist() {
        saved.openIDs = openNotebooks.map(\.id); saved.recentIDs = recentNotebooks.map(\.id)
        saved.activeID = activeID; saved.primaryID = primarySession?.notebook.id; saved.secondaryID = secondarySession?.notebook.id
        saved.splitFraction = splitFraction
        saved.panesReversed = panesReversed
        for session in visibleSessions { if let page = session.page { saved.pages[session.notebook.id] = page.id } }
        let retained = Set(saved.openIDs + saved.recentIDs)
        saved.pages = saved.pages.filter { retained.contains($0.key) }
        guard saved != lastPersisted else { return }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key); lastPersisted = saved }
    }
    private static func validFraction(_ value: Double) -> Double { value.isFinite ? min(0.7, max(0.3, value)) : 0.5 }
    private func unique(_ ids: [UUID]) -> [UUID] { var seen = Set<UUID>(); return ids.filter { seen.insert($0).inserted } }
}
