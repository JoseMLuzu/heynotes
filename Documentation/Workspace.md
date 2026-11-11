# Document tabs and recent notebooks

## Interaction

Opening a notebook in Library adds a tab above the editor. Opening an already-open notebook selects its existing tab instead of creating another. The horizontal row scrolls when needed and scrolls the active tab into view. Covers' colors identify tabs; long titles truncate visually but retain full accessibility labels.

The tab strip now explicitly constrains both its horizontal scroll view and outer row to 44 points at the default text size, scaling with Dynamic Type. Without that bound, the horizontal `ScrollView`/`LazyHStack` could consume a large part of the detail column's height and push notebooks far down the screen. Tabs use narrower titles, an unfilled inactive state, and a subtle selected background/underline. Close and utility controls retain 44-point-wide hit areas. The library detail title uses the inline navigation style to keep content near the top.

- Sidebar button: show/hide the native library sidebar without closing the active editor. In narrow windows it opens the sidebar column. The editor back button still saves and returns to Library.
- Plus button: return to Library to choose another notebook/PDF notebook. It does not create an unwanted blank document.
- Notebook tab: save the outgoing document and load the selected notebook's bookmarked page.
- Close button: close the tab, never delete the notebook. Closing the active tab activates its neighbor; closing the last tab returns to Library.
- Recently Opened menu: reopen one of the latest 20 notebooks, including recently closed tabs. Existing open tabs are reused. During editing, this menu lives inside the upper-right options ellipsis; Library retains its recent-history button.

Open-tab order, active document, recent history and page UUID bookmarks persist locally in a separate versioned UserDefaults value. Restarting restores tabs and the previously active document, or Library if that was the last destination. Missing/deleted documents are removed from restored tab/history lists. If a bookmarked page no longer exists, the first remaining page opens. Bookmarks are retained for open documents and the recent-history window.

The sidebar can also be used to return to Library, Favorites, a folder or Study: leaving an editor waits for a successful save before applying the sidebar selection. Study remains the existing coming-soon view. This work does not implement handwriting recognition or flashcards.

## Save and memory behavior

DocumentWorkspace owns exactly one active EditorSession. Inactive tabs retain metadata and bookmarked page UUIDs, not a separate live PKCanvasView, undo stack or decoded drawing. Existing bounded PDF/thumbnail caches continue to work. Tab switching therefore reloads editable ink from its own file while avoiding one heavy canvas per tab.

Explicit flushing captures the current native canvas drawing before serialization, covering a queued final delegate callback. A tab change, return to Library or active-tab close waits for pending revisions to be saved. If writing fails, the active session and its pending drawing remain in place, and the editor shows the save error. Navigation is blocked during document loads, exports, other active editor operations and active Pencil gestures. Outgoing canvas delegates are detached only after saving and loading the incoming session.

The scene-phase/background save is now owned by the workspace rather than by disappearing EditorView instances. Last-page bookmarks are also updated when the visible page changes. Closing an inactive tab does not unnecessarily flush or replace the active editor. Notebook deletion first removes workspace references so the tab bar never intentionally holds a deleted SwiftData model.

Undo history and zoom/pan position are session-local and reset when leaving/reopening a notebook. Last page and drawing content are preserved. A future per-tab viewport/history feature would need a separate bounded state policy; it is not implied by the current tabs.

## Source changes

- `Features/Workspace/ViewModels/DocumentWorkspace.swift`: restore, save-before-switch, close, recent history, page bookmarks and local preference persistence.
- `Features/Workspace/Views/DocumentTabBar.swift`: horizontal tabs, active state, close controls, Library/plus and recents.
- `Features/Library/Views/LibraryView.swift`: workspace hosting, sidebar transitions and opening notebook cards without stacking multiple editors.
- `Features/Editor/Views/EditorView.swift`: receives the workspace-owned session and returns via the workspace save boundary.
- `Features/Editor/Services/EditorSession.swift`: captures native ink when explicitly flushing.
- `NotesAppDeviceTests/DocumentWorkspaceTests.swift`: tab behavior, persistence, deleted-page fallback and failed-write protection.

There is no SwiftData schema change and no relocation of drawings or PDFs. UserDefaults navigation state is separate from documents and tool preferences.

## Verification

- PASS: simulator app build.
- PASS: all 21 native tests, including four workspace tests and all existing editor, PDF/export, tools and performance tests.
- Workspace tests verify that queued/native ink is flushed to the correct page file, original sessions release their canvas reference, tabs do not duplicate, closing tabs does not delete records, bookmarks survive reopening, missing/deleted documents/pages are handled and failed writes block tab changes/close/Library navigation.

Manual UI review is still needed on the physical iPad: open ordinary and PDF notebooks, switch rapidly, create many tabs, close the active/inactive/last tab, reopen from recents, rotate and resize, use large text/VoiceOver and relaunch. Confirm the tab row remains scrollable and tools remain reachable. Background/relaunch checks should include immediate switching after writing. No claim of hardware Pencil/animation performance is made from these tests.

Compact-layout update (2026-11-09): simulator and signed device builds passed. The update was installed successfully on the iPad Air (5th generation); launch was denied because the iPad was locked. Unlock and open Notes to review the smaller strip with existing tabs. No persistence or workspace switching logic changed. Existing automated workspace tests passed in the preceding 27-test native run; this visual adjustment was verified by compilation, without adding redundant unit tests. The simulator form's remote text-input controls prevented completing an interactive multi-tab visual check, so final layout acceptance remains on the iPad.

## Annotated workflow layout — 2026-11-09

Tabs now share the available strip width equally according to the number of open notebooks. A 140-point minimum (scaled with Dynamic Type) preserves readable titles and separate 44-point close targets; overflow scrolls horizontally. Active tabs remain in view after selection, resizing and tab-count changes. The sidebar button has its own action and uses NavigationSplitView column visibility / preferred compact column bindings, available at the iPadOS 17 target. Opening/closing the sidebar does not replace the editor session.

The editor owns its tab-row presentation so its existing page options can render directly at the upper-right end of that row. Library shows the same tab component when no editor is active. There is one tab row and one live editor; models, save boundaries, tab order and local restoration format are unchanged. The + action still returns to Library. The editor's lower row retains only the direct bookmark toggle and page counter at the right; save status is next to the notebook title, matching the annotated design.

The user selected a fixed task-based tool order, rather than automatic frequency-based movement. Writing and erasing come first, followed by stroke settings, selection, shapes/study tape/insertion, undo/redo and the palette launcher. Ruler is in Shapes and in Page Options. No usage analytics or adaptive reorder is introduced. The palette launcher is pinned after the scrolling tools and remains reachable in narrow windows.

Validation: all 48 native regression tests pass. An expanded native rendering fixture opens four real notebook/page records through DocumentWorkspace and captures the complete editor in landscape, portrait and a narrow iPad window; all three captures were visually inspected. The signed generic iOS build passes. Actual Pencil interaction and sidebar presentation still require the normal physical-device acceptance check.

## Glass controls and tab-only document title — 2026-11-09

The editor's secondary row no longer repeats the notebook name or cover-color rule. The active document is named in its tab. The small blue/orange save dot remains beside the Back to Library control with its existing accessible status. The freed width goes to the tool strip.

Tools and bookmark/page controls now use capsule-shaped surfaces. EditorGlassCapsule applies the public SwiftUI glassEffect API on iPadOS 26+, verified in the installed SDK, with regular Material on iPadOS 17–25. Reduce Transparency selects an opaque semantic surface and a quiet border. The deployment target stays iPadOS 17. Selected tool backgrounds are circular. The header backdrop matches the canvas, and the old full-width divider/surface is removed so the controls feel separate from the paper. PencilKit rendering, persistence and tool order are unchanged.

The signed device build passes. The native editor rendering fixture covers landscape, portrait, narrow-window dark mode and landscape light mode. Reduce Transparency and minimum-OS fallback need manual runtime review; their availability branches compile against the 17.0 deployment target.

## Glass navigation band — 2026-11-09

The tab row now shares the editor's native glass/material policy through EditorGlassSurface. It uses a single rounded-rectangle band (16-point corners), while drawing controls keep their capsule shape. Sidebar, open-document and options controls stay inside the shared band. Individual inactive tabs have no separate glass surface. The active tab has a quiet accent fill and a two-point underline using the notebook cover color.

The band retains 44-point default-height hit targets, its own explicit vertical sizing and equal-width/overflow behavior. A two-point bottom inset plus the tool row's six-point top inset creates an eight-point visual gap. The navigation band's outer insets align with the tool row. Native glass is guarded for iPadOS 26; earlier versions use Material, and Reduce Transparency retains the opaque fallback. No navigation, file, palette or persistence behavior changes.

Validation: signed iOS build and the existing native editor rendering test pass. Its landscape dark/light, portrait and narrow-window captures were visually inspected. Physical Reduce Transparency and minimum-OS appearance remain manual checks.

## Undo/redo beside bookmarks — 2026-11-09

Undo and redo now live at the left of the bookmark/page-count glass capsule, separated from page navigation by a short divider. They are removed from the writing-tool strip. Both retain 44-point hit targets and their accessible labels, and continue to use the active canvas's UndoManager. Page loading/other busy operations block the group; unavailable pages disable undo/redo. No history or persistence behavior changes.

## Save status in the active tab — 2026-11-09

The blue/orange save dot now follows the active document tab, immediately after its title and before the close action. It is removed from the editor control row. Inactive tabs and Library do not imply an active save state. Color and error/pending behavior are unchanged; the active tab's VoiceOver value announces the actual session status, with help text on the dot. Tab widths and close hit targets remain unchanged.

## Standalone sidebar control — 2026-11-09

The sidebar toggle now sits outside the tab band's glass surface, at the left edge and aligned with the editor's Back to Library control. It uses a plain system icon with the existing 44-point hit target. The tab strip alone owns the glass background; sidebar visibility, keyboard/accessibility behavior and active-document persistence are unchanged.

## Library document opening zoom — 2026-11-09

Selecting a notebook or PDF card now opens the editor with a 0.28-second zoom originating at that cover's measured global frame. The library fades behind the incoming document. Preference geometry records the actual visible cover, so opening from folders, Favorites, search results or a scrolled grid uses the selected item's position.

The workspace keeps its existing load/save boundary: loading completes before publication, then the visual transition begins. DocumentOpeningZoom changes only scale, translation and opacity around a fixed destination viewport; it does not animate the live PencilKit canvas bounds, serialize drawings or allocate a separate canvas per frame. Inputs are gated for the short transition to avoid accepting a Pencil stroke against a moving surface. There is no added wait before loading or showing the editor.

The effect is scoped to library-card selections. Tab switches, recent-history selection, startup restoration, returning to Library and page turns retain their existing behavior. Reduce Motion bypasses zoom and the extra input gate. Unavailable source geometry falls back to direct opening. No persistent schema or file format changes.

Validation: all 49 native regression tests pass. DocumentOpeningTests renders the opening at progress 0, 0.5 and 1 and verifies that canvas identity, bounds and editable ink remain unchanged. The signed generic iOS build passes. Manual acceptance: open notebooks/PDFs at different grid positions and after scrolling; check the short zoom, input after completion, Reduce Motion, failed-document recovery and an unchanged tab/page navigation workflow.
