import Foundation
import Observation

@MainActor @Observable
final class PDFImportSelection {
    enum Mode: String, CaseIterable { case all = "Entire Document", selected = "Choose Pages" }
    let draft: PDFImportDraft
    var mode: Mode = .all
    var rangeText = ""
    private(set) var selected: Set<Int> = []
    private(set) var rangeError: String?
    private(set) var importing = false
    var errorMessage: String?

    init(draft: PDFImportDraft) { self.draft = draft }
    var indices: [Int] { mode == .all ? Array(0..<draft.pageCount) : selected.sorted() }
    var count: Int { mode == .all ? draft.pageCount : selected.count }
    var canImport: Bool { count > 0 && !importing && (mode == .all || rangeError == nil) }
    var importTitle: String { "Import \(count) \(count == 1 ? "Page" : "Pages")" }
    func contains(_ index: Int) -> Bool { mode == .all || selected.contains(index) }

    func toggle(_ index: Int) {
        guard !importing, (0..<draft.pageCount).contains(index) else { return }
        rangeError = nil
        if mode == .all { mode = .selected; selected = [index] }
        else if selected.contains(index) { selected.remove(index) }
        else { selected.insert(index) }
    }
    func clear() { guard !importing else { return }; mode = .selected; selected = []; rangeError = nil }
    func applyRange() {
        guard !importing else { return }
        do {
            selected = Set(try PDFPageSelection.parse(rangeText, pageCount: draft.pageCount))
            mode = .selected; rangeError = nil
        } catch { rangeError = error.localizedDescription }
    }

    func confirm(using action: ([Int]) async -> String?) async -> Bool {
        guard canImport else { return false }
        importing = true; errorMessage = nil
        defer { importing = false }
        errorMessage = await action(indices)
        return errorMessage == nil
    }
}
