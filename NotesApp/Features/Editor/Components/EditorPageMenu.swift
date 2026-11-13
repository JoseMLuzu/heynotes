import UIKit

/// Prebuilt native menu for the tab strip's ellipsis; document work stays in the session.
@MainActor struct EditorPageMenu {
    enum Destination { case content, margin, templates, delete, focus }
    let session: EditorSession
    let workspace: DocumentWorkspace?
    let palette: QuickPalettePreferences
    let placement: EditorToolbarPreferences
    let fingerDrawing: Bool
    let setFingerDrawing: (Bool) -> Void
    let present: (Destination) -> Void
    let share: (URL) -> Void

    func make() -> UIMenu {
        let ready = session.ready && !session.busy
        let pages: [UIMenuElement] = [
            session.page?.pdfFilePath != nil
                ? item("PDF Note Margin", "rectangle.righthalf.inset.filled", enabled: ready) { present(.margin) }
                : item("Page Template", "square.grid.2x2", enabled: ready) { present(.templates) },
            item("Duplicate Page", "plus.square.on.square", enabled: ready) { Task { await session.duplicatePage() } },
            item("Move Page Earlier", "arrow.left", enabled: ready && (session.page?.pageIndex ?? 0) > 0) { session.movePage(-1) },
            item("Move Page Later", "arrow.right", enabled: ready && (session.page?.pageIndex ?? 0) < session.notebook.pages.count - 1) { session.movePage(1) },
            item("Delete Page", "trash", enabled: ready && session.notebook.pages.count > 1, destructive: true) { present(.delete) }
        ]
        var pageOptions = pages
        if !session.elements.isEmpty {
            pageOptions.insert(item("Inserted Content", "square.on.square", enabled: ready) { present(.content) }, at: 1)
        }
        let positions = EditorToolbarPosition.allCases.map { position in
            item(position.title, position.symbol, checked: placement.position == position) { placement.position = position }
        }
        var workspaceOptions: [UIMenuElement] = [
            UIMenu(title: "Toolbar Position", image: UIImage(systemName: "rectangle.3.group"), options: .singleSelection, children: positions),
            UIMenu(title: "Quick Palette", image: UIImage(systemName: "paintpalette"), children: [
                item(palette.isVisible ? "Hide Quick Palette" : "Show Quick Palette", "paintpalette", enabled: ready) {
                    if palette.isVisible { palette.isVisible = false } else { palette.show() }
                },
                item("Restore Position", "arrow.counterclockwise", enabled: ready) {
                    palette.place(PalettePosition()); palette.show()
                }
            ])
        ]
        if let workspace, !workspace.recentNotebooks.isEmpty {
            workspaceOptions.append(UIMenu(title: "Recently Opened", image: UIImage(systemName: "clock.arrow.circlepath"),
                                           children: workspace.recentNotebooks.map { notebook in
                item(notebook.title) { Task { await workspace.open(notebook) } }
            }))
        }
        workspaceOptions += [
            item("Draw with Finger", "hand.draw", checked: fingerDrawing) { setFingerDrawing(!fingerDrawing) },
            item(session.hasPendingSave && session.errorMessage != nil ? "Retry Saving" : "Save Now", "square.and.arrow.down", enabled: ready) {
                Task { _ = await session.flush() }
            }
        ]
        let export = UIMenu(title: "Export PDF", image: UIImage(systemName: "square.and.arrow.up"), children: [
            UIDeferredMenuElement.uncached { completion in
                Task { @MainActor in completion(await makeExportItems()) }
            }
        ])
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [
                item("Add Page", "plus", enabled: ready) { Task { await session.addPage() } },
                item("Focus Mode", "viewfinder", enabled: ready) { present(.focus) },
                export
            ]),
            UIMenu(options: .displayInline, children: [
                UIMenu(title: "Page", image: UIImage(systemName: "doc"), children: pageOptions),
                UIMenu(title: "Workspace", image: UIImage(systemName: "rectangle.3.group"), children: workspaceOptions)
            ])
        ])
    }

    /// Deferred until Export is opened; archived page content is decoded off the main actor.
    func makeExportItems() async -> [UIMenuElement] {
        var result: [UIMenuElement] = [
            exportItem("Current Page", currentOnly: true),
            exportItem("Entire Notebook", currentOnly: false)
        ]
        let currentHasTape = session.elements.contains { $0.kind == .tape }
        var notebookHasTape = currentHasTape
        if !currentHasTape {
            let otherContent = session.notebook.pages.filter { $0.id != session.page?.id }.compactMap(\.objectsData)
            notebookHasTape = await Task.detached(priority: .utility) {
                otherContent.contains { data in
                    (try? PageElementsCodec.decode(data).contains { $0.kind == .tape }) == true
                }
            }.value
        }
        if notebookHasTape {
            var practice: [UIMenuElement] = []
            if currentHasTape { practice.append(exportItem("Current Page (Covered)", currentOnly: true, tape: true)) }
            practice.append(exportItem("Entire Notebook (Covered)", currentOnly: false, tape: true))
            result.append(UIMenu(title: "Practice", image: UIImage(systemName: "rectangle.on.rectangle"), children: practice))
        }
        return result
    }

    private func exportItem(_ title: String, currentOnly: Bool, tape: Bool = false) -> UIAction {
        item(title, "square.and.arrow.up", enabled: session.ready) {
            Task { if let url = await session.export(currentPageOnly: currentOnly, includeStudyTape: tape) { share(url) } }
        }
    }

    private func item(_ title: String, _ symbol: String? = nil, enabled: Bool = true,
                      checked: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> UIAction {
        var attributes: UIMenuElement.Attributes = []
        if !enabled { attributes.insert(.disabled) }
        if destructive { attributes.insert(.destructive) }
        return UIAction(title: title, image: symbol.flatMap(UIImage.init(systemName:)),
                        attributes: attributes, state: checked ? .on : .off) { _ in action() }
    }
}
