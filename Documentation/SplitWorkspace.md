# Two-document workspace

## Behavior and navigation

The editor can show two different notebooks or PDF-backed notebooks in the same app window. Use the split icon beside the tabs to choose a second document. Touch and hold an existing document tab and choose Open Beside as a shortcut. With two panes, the same split menu offers another adjacent document, Swap Panes and Keep Focused Document Only. A pane's close button closes its tab without deleting the notebook; keeping a focused document retains the other file as an ordinary tab.

At widths of at least 780 points, the workspace places editors side by side. Narrower windows stack them vertically. The divider can be dragged and has a VoiceOver adjustable action. Preferred proportions are limited to 30–70 percent and further constrained to usable pane minimums in the current window. Only the end of a divider drag writes the preference. Two live editors remain mounted through resizing and Focus Mode; the hidden Focus Mode pane cannot receive input or accessibility focus.

The shared tab strip appears once. Each pane has its own title/focus indicator, toolbar, page controls, PencilKit canvas, Undo manager, scroll/zoom, palette and page navigation. Existing toolbar-placement preferences still apply. Tool and palette instances are independent while the editors are mounted; device defaults provide initial styles for newly created editors. Tapping a pane title or touching its canvas focuses it. Tab activation focuses an already visible document or replaces the focused pane with a different tab. Open Beside keeps the focused document and replaces the other pane.

## State and identities

DocumentWorkspace owns at most two EditorSessions in stable primary/secondary slots. activeSession remains the focused session so existing tab, Study and navigation consumers retain their API. Editor chrome is keyed by slot, preserving existing native toolbar controls and horizontal scroll position during ordinary tab replacement. Pane swaps reorder those stable slot views rather than moving sessions between slots. Closing the other pane or keeping the secondary pane does not relocate the retained session to a new view identity. Canvas IDs still follow the document; different documents never share one editable canvas.

WorkspaceSnapshot retains the shipped workspace.tabs.v1 preference key and its legacy fields, adding only optional pane IDs, fraction and display-order state. Legacy single-editor JSON remains decodable. Restoring checks currently available, non-trashed notebooks, individual permanent page IDs and shared-drawing safety. Missing/trashed neighbors are pruned without deleting document records or files. Saved page positions are maintained for both editors. SwiftData entities, metadata schema and drawing-file layout are unchanged; no store migration is required.

## Save and interaction safety

Closing the only visible editor while other tabs remain first saves its ink and loads the successor without detaching the outgoing canvas. Once the successor is ready, it replaces the outgoing session in the same presentation slot. Library is never published as an intermediate state, and native editor controls remain mounted. A failed save or an invalid successor retains the current tab. Closing one of two visible editors keeps the other editor; closing the final tab intentionally returns to Library.

Replacing/closing a visible pane flushes its actual native PencilKit drawing before detaching its canvas. Leaving for Library, keeping one focused document or forgetting an affected subtree validates the relevant saves before changing layout/references. A failed save retains the existing sessions and pending ink. Backgrounding requests each editor's existing save operation. Native pen/paging/zoom behavior stays inside the current PaperCanvas implementation. At most two editor sessions and their existing bounded neighbor caches are retained; memory warnings discard prepared pages for both editors.

A passive native PaneTouchObserver receives the initial contact and fails immediately. It does not cancel/delay touches or prevent PencilKit/page gestures. This lets focus update before a Pencil stroke without overlay hit targets or a drag recognizer on the page. Only the focused editor processes Pencil double-tap; asynchronous image/card operations remain valid for their original visible session even if the user focuses the other pane. Source-note opening through Study uses the same explicit-page workspace API and save boundary.

The same notebook cannot occupy both panes. Opening it from another tab instead focuses its existing pane. Different notebooks that reference the same editable drawing path are rejected, including redundant path separators/dot components. Immutable source PDF and image reuse remains permissible; only editable drawing-path aliasing is excluded. This avoids two sessions overwriting the same ink file. No documents are duplicated to provide split view.

## APIs and compatibility

The project remains iPadOS 17+. GeometryReader with AnyLayout/HStackLayout/VStackLayout provides the adaptive arrangement; it does not depend on macOS-only HSplitView. Native UIViewRepresentable/PencilKit integrations remain public APIs. Apple's [GeometryReader documentation](https://developer.apple.com/documentation/swiftui/geometryreader) describes the geometry-driven layout boundary. The touch observer uses public UIGestureRecognizer overrides and does not synthesize system events.

## Acceptance checks

1. Open a notebook, choose the split icon and select another notebook or PDF. Confirm two editable documents and one shared tab strip.
2. Write different strokes in both panes. Change tools, turn a page, zoom and undo independently. Apple Pencil double-tap should change only the focused pane's tool.
3. Activate an already visible tab, then replace one pane with a third tab. The untouched pane must keep its ink, page, canvas and Undo history.
4. Drag the divider, rotate/use a narrow window, swap panes, enter/exit Focus Mode and keep one document only. The retained document must not reload its canvas or lose Undo/ink.
5. Close either pane, reopen tabs, return to Library, background/relaunch and verify both saved drawings and remembered page positions. Restore a previously persisted split.
6. Move a visible notebook/folder to Trash through Library; confirm saved ink and valid tabs. Test an unavailable source/page and a failed save without discarding pending ink.
7. Compare a PDF and handwritten notes, export each separately and confirm the PDF source bytes/dimensions remain unchanged.

Runtime UI and drawing tests use the iPadOS 26.5 simulator; iPadOS 17 is compile-checked. Hardware Pencil latency, gesture feel, VoiceOver and actual display frame pacing remain physical iPad acceptance checks. Same-document dual views and opening more than two live editors are outside this implementation.

## Automated verification

The full native suite passed 141 tests with the two-editor implementation. Following a final shared-Focus-policy correction, nine focused tests passed (six split-workspace cases and three existing Focus Mode cases). New coverage exercises actual separate PKCanvasViews, distinct saved ink, independent eraser toggles and focused-only Pencil double-tap callbacks, native Undo retention, initial-contact focus without gesture cancellation, stable view/canvas identity through resize/swap/keeping the secondary pane, legacy tab-state decoding, restored page UUIDs/order/proportions, missing/trashed and aliased-drawing rejection, save failures preserving both sessions and ink, background saves, independent PDF/page navigation and export/source geometry. A real NavigationSplitView also verifies one shared sidebar gesture policy is restored after Focus Mode; the two editor children do not compete to save/restore that native property.

The existing regression for native toolbar-button identity and tab-strip offset across tab switches passes after using stable presentation-slot identities. Landscape, narrow stacked and Focus Mode screenshots were exported and visually inspected. The signed optimized Release build succeeds. These checks establish persistence, geometry and object identity, not hardware Pencil latency or display FPS. No host tests were added because the changed runtime services depend on the iPad editor; the existing pure metadata code/schema is unchanged.

The Release update installed successfully over the existing iPad app on November 13, 2026 (installation sequence 2876), retaining the bundle ID and store. Source and documentation changes remain local and uncommitted.
