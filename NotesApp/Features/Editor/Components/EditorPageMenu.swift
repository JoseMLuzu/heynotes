import UIKit

/// Prebuilt native menu for the tab strip's ellipsis; document work stays in the session.
@MainActor struct EditorPageMenu {
    enum Destination { case content, margin, templates, delete, focus, settings }
    let session: EditorSession
    let workspace: DocumentWorkspace?
    let palette: QuickPalettePreferences
    let tools: ToolPreferences
    let placement: EditorToolbarPreferences
    let fingerDrawing: Bool
    let setFingerDrawing: (Bool) -> Void
    let present: (Destination) -> Void
    let share: (URL) -> Void

    func make() -> UIMenu {
        let positions = EditorToolbarPosition.allCases.map { position in
            item(position.title, position.symbol, checked: placement.position == position) { placement.position = position }
        }
        var document: [UIMenuElement] = [
            item("Focus Mode", "viewfinder", enabled: session.ready) { present(.focus) },
            item("Settings", "gearshape") { present(.settings) },
            item("Add Page", "plus", enabled: session.ready) { Task { await session.addPage() } },
            item(palette.isVisible ? "Hide Quick Palette" : "Show Quick Palette", "paintpalette", enabled: session.ready) {
                if palette.isVisible { palette.isVisible = false } else { palette.show() }
            },
            item("Restore Quick Palette Position", "arrow.counterclockwise", enabled: session.ready) {
                palette.place(PalettePosition()); palette.show()
            }
        ]
        if let workspace {
            document.append(UIMenu(title: "Recently Opened", image: UIImage(systemName: "clock.arrow.circlepath"),
                                   children: workspace.recentNotebooks.map { notebook in
                item(notebook.title) { Task { await workspace.open(notebook) } }
            }))
        }
        let export = UIMenu(title: "Export PDF", image: UIImage(systemName: "square.and.arrow.up"), children: [
            exportItem("Export Page (Without Study Tape)", currentOnly: true),
            exportItem("Export Notebook (Without Study Tape)", currentOnly: false),
            exportItem("Export Practice Page (Covered)", currentOnly: true, tape: true),
            exportItem("Export Practice Notebook (Covered)", currentOnly: false, tape: true)
        ])
        var content: [UIMenuElement] = [
            item("Save Now", "square.and.arrow.down", enabled: session.ready) { Task { _ = await session.flush() } },
            item("Inserted Content", "square.on.square") { present(.content) }
        ]
        if session.page?.pdfFilePath != nil {
            content.append(item("PDF Note Margin", "rectangle.righthalf.inset.filled") { present(.margin) })
        }
        content += [
            item("Ruler", "ruler", checked: tools.rulerEnabled) { tools.rulerEnabled.toggle() },
            item("Page Template", "square.grid.2x2", enabled: session.ready && session.page?.pdfFilePath == nil) { present(.templates) },
            item("Draw with Finger", "hand.draw", checked: fingerDrawing) { setFingerDrawing(!fingerDrawing) }
        ]
        let pages: [UIMenuElement] = [
            item("Duplicate Page", "plus.square.on.square", enabled: session.ready) { Task { await session.duplicatePage() } },
            item("Move Page Earlier", "arrow.left", enabled: (session.page?.pageIndex ?? 0) > 0) { session.movePage(-1) },
            item("Move Page Later", "arrow.right", enabled: (session.page?.pageIndex ?? 0) < session.notebook.pages.count - 1) { session.movePage(1) },
            item("Delete Page", "trash", enabled: session.notebook.pages.count > 1, destructive: true) { present(.delete) }
        ]
        return UIMenu(children: [
            UIMenu(title: "Toolbar Position", image: UIImage(systemName: "rectangle.3.group"), options: .singleSelection, children: positions),
            UIMenu(options: .displayInline, children: document),
            export,
            UIMenu(options: .displayInline, children: content),
            UIMenu(options: .displayInline, children: pages)
        ])
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
