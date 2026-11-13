import SwiftUI

/// Observe ink settings here so slider/color changes do not rebuild navigation and menus.
struct EditorCanvasContent: View {
    let session: EditorSession
    let tools: ToolPreferences
    let fingerDrawing: Bool
    var onPencilDoubleTap: ((UIPencilPreferredAction) -> Void)? = nil
    var onInteraction: (() -> Void)? = nil

    var body: some View {
        PaperCanvas(session: session, tool: tools.tool, fingerDrawing: fingerDrawing,
                    editorTool: tools.selected, inkStyle: tools.ink, rulerEnabled: tools.rulerEnabled,
                    onPencilDoubleTap: onPencilDoubleTap, onInteraction: onInteraction)
    }
}
