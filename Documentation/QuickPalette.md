# Quick Palette

## Interaction

The editor offers a floating favorites palette over its writing viewport. Five real configurations are included initially: blue pen, red pen, graphite pencil, yellow highlighter and precise eraser. Multiple named profiles each hold up to six favorites, including several configurations of the same tool. Existing top tools remain available and stay synchronized with the selected configuration.

- Tap a favorite to restore its tool, ink color, width and opacity, or eraser mode/size. The selected indication compares the full effective configuration rather than only the tool type.
- Hold a direct tool icon in the main toolbar and drag it into the palette. The palette reveals/expands when the drag starts. Drop onto a favorite to insert at that position, or onto **+**, the grip/header or other palette space to append. The source toolbar tool remains available.
- Hold and drag a palette favorite onto another favorite to reorder it. Dropping elsewhere within the palette moves it to the end. Hover highlights the palette and target; saved order changes only after dropping.
- Drag the **grip** with one finger to move the palette. Only that handle has a pan recognizer; it accepts direct touch and excludes Pencil input. Tool buttons do not move the palette.
- Tap **−** to collapse the box into a small grip/expand control. The grid button expands it again. The writing canvas retains its clean bottom edge.
- Tap **… → Customize Favorites** to edit names/settings, remove favorites or use Edit to reorder. At least one favorite is kept.
- **+** captures the current tool as a draft. Long-press a favorite to edit it or replace it with the current tool. Save commits a draft; Cancel leaves both the saved favorite and active tool unchanged.
- The **profile name selector** below the favorites switches profiles. **Manage Profiles** creates, duplicates, renames or deletes them. A new profile starts with the current tool; a duplicate gets independent copies of all favorites. Deletion requires confirmation, and at least one profile is kept. Names are trimmed, limited to 40 characters and unique ignoring case.
- **… → Move to Corner** provides accessible alternatives to dragging. Hide the palette from this menu. The **paint palette button pinned at the right end of the tools** brings it back expanded. **Page Options (…) → Show Quick Palette** also restores it while preserving favorites and position. **Restore Quick Palette Position** resets the viewport position and reveals it. These actions stay near the top of the header menu, reachable even when the floating palette is hidden or outside a resized viewport.


Saved favorites do not change when the top toolbar's settings are adjusted. Applying a favorite updates the active tool preferences, so normal tool switching still remembers each tool's latest settings. Saving an edited favorite does not automatically apply it; tap the favorite to use it.

Switching profiles changes the available favorites without automatically changing the active writing tool. The last selected profile persists across notebooks and launches. The viewport anchor, visibility and collapsed state are shared across profiles; the box can adjust its size/clamping when the favorite count changes. Editing drafts retain their source profile UUID: saving after a selection change updates the original profile, and saving to a deleted profile is rejected rather than writing to another profile.

## Position, input and rendering

The expanded box uses a 3-column grid of 44-point buttons and a 44-point profile selector; five/six favorites occupy approximately 156 × 204 points. The collapsed control is 108 × 60 points. Tool symbols retain a readable primary color and show ink color in a bordered dot, including very light colors. Names and configuration values are exposed to accessibility.

Position is stored as a fraction of the available viewport travel, excluding the header. Dragging clamps the box to that viewport and snaps within 20 points of the nearest edge, including when both edges are close in a short window. Rotation/resizing recomputes the origin from the normalized position. A viewport too small for the expanded box automatically uses the compact control; its button opens customization if expansion cannot fit. If even the compact control cannot fit, the overlay hides instead of placing interactive controls off-screen. The pinned palette launcher and header-menu restore action remain available.

Only palette content participates in hit testing; no full-viewport gesture or background is installed. Drag translation is local view state. Preferences are written at the end of a completed drag, not on every movement; cancelled drags do not save a new location. The drag handle and tool application check for active Pencil strokes. Busy document operations disable palette interactions. Collapse animation respects Reduce Motion; dragging never triggers drawing-file writes or alters page coordinates.

## Data and compatibility

`QuickPalettePreferences` now stores a versioned profile archive under the local `editor.quickPalette.v2` UserDefaults key. It includes profiles, active profile UUID and shared presentation state. On first upgrade, the v1 favorites become **My Palette**, preserving favorite UUIDs, effective settings, order, position, visibility and collapsed state. The original v1 bytes are retained unchanged; subsequent launches use v2. Fresh defaults are persisted once so profile/favorite IDs remain stable even before the first edit.

Profiles and presets use stable UUIDs. Duplication creates new profile/favorite IDs and independent value copies. Numeric settings are sanitized against PencilKit's supported ranges; positions are bounded and duplicate/excess favorite entries are filtered. An unreadable v2 blob is retained under `editor.quickPalette.v2.recovery` before fallback to the retained v1 or initial profile. This recovery concerns preferences only, not notebook content. There is no automatic backport of later profile edits into the retained v1 archive.

The existing `editor.tools.v1` preference format is unchanged. There is no SwiftData migration, cloud/network dependency, drawing-file relocation or PDF/export change. UIKit is used only for the finger-specific pan recognizer; presentation and customization use SwiftUI.

The restore action addresses recovery after closing the palette: it is permanently available near the top of the header menu, and revealing it clears the persisted collapsed flag. Existing hidden preferences do not require a reset or reinstall. A regression test covers hiding/collapsing, reopening preferences, restoring from the header and retaining favorites/position.

## Files

- `Services/ToolPreset.swift`: configuration snapshots, validation, capture/apply/matching.
- `Services/QuickPalettePreferences.swift`: favorites persistence and viewport placement math.
- `Components/PaletteDragHandle.swift`: direct-touch-only UIKit pan bridge.
- `Components/QuickPalette.swift`: floating/collapsed UI, menus and editing entry points.
- `Components/PaletteManager.swift`, `ToolPresetEditor.swift`: ordered favorites and isolated editable drafts.
- `Components/PaletteProfileManager.swift`: profile selection/creation/duplication/rename and confirmed deletion.
- `EditorView.swift`: viewport overlay and visibility toggle.
- `NotesAppDeviceTests/QuickPaletteTests.swift`: independent configurations, persistence/limits/order and placement regressions.
- `NotesAppDeviceTests/PaletteProfileTests.swift`: actual v1 JSON migration, profile isolation/lifecycle and source-bound draft saves.

Paths above are relative to `NotesApp/Features/Editor`, except the test file.

## Verification and remaining acceptance

All 35 native simulator tests passed, including four palette tests, three profile tests and existing editor, save/recovery, page gestures, PDF/export, cover, template, cache and tool tests. They verify independent blue/red pen settings, native precise eraser construction, persisted edits/order/visibility/position, six-favorite capacity, draft isolation, one-favorite minimum, rotation bounds, nearest-edge snapping and restoration after hiding/collapsing and relaunch. Profile tests cover v1 migration with original-byte preservation, independent duplication IDs/configurations, unique names, last-profile protection, selected-profile restoration and stale-draft safety. Initial favorites normalize native Pencil width limits before storage, keeping settings consistent after reopening.

The simulator and signed device builds passed. The feature was installed and launched on the connected iPad Air. The first off-screen SwiftUI ImageRenderer snapshot could not render native Menu/UIViewRepresentable content; a UIKit-hosted snapshot is used for the actual palette controls. Interactive simulator text entry was unavailable through the remote Device Hub controls, so a complete editor interaction walkthrough remains a physical-device acceptance task.

Profile delivery: the signed profile update installed successfully over the existing Notes app on the connected iPad Air. Its UIKit-hosted palette snapshot was reviewed with the visible profile-name selector. The final singular/plural favorite-count wording was compiled after the 35-test run. Manually check native profile naming alerts, confirmation/cancellation and quick switching on the physical device; automated preference migration uses a representative v1 fixture rather than a copy of the user's private settings.

On iPad: apply both pen colors and confirm different strokes; save a custom color/width; edit/cancel/replace/reorder; drag only by the grip with a finger; confirm Pencil does not move it; collapse/expand/hide/restore; rotate and use split-screen; relaunch and switch tabs; write and pan outside the palette; check VoiceOver corner movement, long names, contrast and large text. Verify actual Apple Pencil responsiveness before making latency claims.

## Compact header — 2026-11-09

The right side now uses one compact group with the current-page bookmark toggle, tappable page count, and options menu. The standalone palette launcher, grid glyph and Add Page button were removed from that row. Add Page and Show/Hide Quick Palette are near the top of the options menu; the page-index + action and hold-to-create gesture remain available. PDF export variants share an Export PDF submenu. The save-status dot stays separate at the far-right edge. This presentation change does not modify documents or saved palette profiles. The native editor rendering test and signed device build pass.

## Fixed tool order and pinned launcher — 2026-11-09

The paint-palette launcher is again visible at the right end of the tool strip, after undo/redo. It stays outside the horizontal tools scroll view so it remains reachable in narrow windows. It expands a hidden/collapsed palette or hides an expanded palette; its context menu restores the position. The options menu remains an additional recovery path. Tools have a stable task-based order selected by the user; palette profiles remain customizable and no usage-driven sorting runs.

## Launch redraw-loop correction — 2026-11-11

Restoring an active editor after adding the library AppStorage sort preference exposed a feedback loop. Reconstructing EditorView initializes a temporary QuickPalettePreferences value before SwiftUI restores its retained State. Its initializer unconditionally persisted the palette. That defaults notification invalidated the library sort preference, reconstructed the editor and wrote the palette again. Device watchdog reports showed repeated SwiftUI observation/graph updates, and temporary view-invalidation logging identified the sort preference. A read-only local metadata/preferences copy reproduced the frozen startup in the simulator; the same reproduction yielded normally after this correction. Diagnostic copies and temporary logging are not bundled or committed.

Saved palette state now supports semantic equality. persist() compares the decoded existing state with the sanitized current state and skips equal writes. JSON byte order is deliberately irrelevant. Actual edits, first creation, legacy migration and repair of invalid state still persist; profiles, favorites, visibility and position are preserved. This also suppresses no-op setters without replacing the retained editor or removing the PDF previews/sort menu.

The regression suite counts actual UserDefaults writes while repeatedly reopening a valid palette, checks a real edit writes once, and hosts LibraryView restoring an editor with Type sorting and the folder sidebar visible. It verifies repeated main-actor yields, returning to Library, activating the native sort action, reopening the notebook and unchanged palette/ink bytes. A columnVisibility initializer argument lets the test cover the real visible-sidebar layout while preserving the normal automatic default. No schema migration or user-file changes are required.

## Toolbar drag and palette reordering — 2026-11-14

Direct pen, pencil, highlighter, eraser, lasso, object-selection and tape buttons use the system's long-press drag interaction. Normal taps keep their existing immediate select/settings action; no custom long-press recognizer or timer is added to those buttons. Settings, insertion and grouped shape menus remain menus. Existing customization and accessible list reordering remain available as drag alternatives.

`ToolPreferences.capturePreset(for:)` snapshots an inactive tool's own saved color/width/opacity or eraser mode/size without selecting it or writing tool preferences. A drag carries that immutable value through a bounded, versioned JSON item provider under `com.local.notesapp.palette-tool`, visible only within the application process. No file paths, drawing bytes, SwiftData objects or document content enter this payload. The UTI is declared in Info.plist and uses public iPadOS-17-compatible APIs.

The drop destination covers only the palette rectangle, preserving writing and pan outside it. Grid geometry maps the actual pointer location to the 44-point favorite cells. Hover updates outlines only; it does not persist, reorder or apply a tool. Dropping a toolbar tool creates a fresh favorite UUID in the captured active profile. Same-owner/same-profile favorite drops reorder the current stored item and preserve its ID/settings; cross-profile or other-pane drops copy the snapshot with a new ID and do not remove the source. At capacity, reordering still works; adding a seventh favorite is rejected with a brief inline and VoiceOver notice. Existing favorites are never silently overwritten.

Provider loading starts synchronously inside `performDrop`, as required by the native API; delivery returns to the main actor. The receiver rechecks interaction permission, destination profile and target identity before committing. Late drops after switching profiles, missing favorites, unsupported payload versions, oversized/malformed data, unrelated providers and multi-item drops fail without changing favorites. Busy/exporting, detached-editor and active-Pencil-stroke guards prevent applying late UI changes. Position/favorites are unchanged by cancellation; starting a toolbar drag intentionally reveals the palette. Dragging a favorite in Focus Mode does not change a previously hidden palette preference.

The profile archive stays at `editor.quickPalette.v2`; no SwiftData migration or document-file change is needed. Reorder animation is limited to the palette grid and respects Reduce Motion. Helper files: `Services/PaletteToolDrag.swift`, `Components/PaletteToolDragSource.swift` and `Components/PaletteToolDrop.swift`. Native regression coverage lives in `NotesAppDeviceTests/PaletteToolDragTests.swift`.

Manual device acceptance: short-tap each tool and open its settings; drag inactive pen/pencil/highlighter/eraser icons with distinct settings; cancel a drag; insert onto a slot and append through +/header; reorder up/down and at six-favorite capacity; switch profiles/relaunch; repeat with top/bottom/side toolbars and both documents open. Confirm no accidental mark, page turn or palette movement, and check the grip/menu alternatives with VoiceOver. Automated providers and installed UIKit interactions do not establish physical finger/Pencil gesture feel.

Apple reference: [SwiftUI DropDelegate](https://developer.apple.com/documentation/swiftui/dropdelegate) and [starting provider loading in performDrop](https://developer.apple.com/documentation/swiftui/dropdelegate/performdrop(info:)).

Delivery verification: all **157 native simulator tests** pass, including six new drag/provider/profile/capacity/layout cases and existing toolbar, tool-preference, Pencil, page gestures, Focus Mode and split-workspace coverage. Signed physical-iPad Release build passes. The six-favorite side-toolbar screenshot was inspected. Logs: `/private/tmp/heynotes-palette-drag-full-tests.log` and `/private/tmp/heynotes-palette-drag-release.log`. An earlier 28-test focused run had one sidebar-gesture assertion failure in FocusModeTests; that same test and the complete suite subsequently passed without changing focus behavior. Keep the timing-sensitive test result available for the quality phase rather than treating the first run as a clean pass.

## Icon-only drag preview

Dragging a toolbar tool or reordering a palette favorite now shows only its SF Symbol in its saved ink color (or the app accent for non-ink tools). The name/detail card, material background and rectangular padding container are removed. The native drag-preview outline is circular, while the normal button retains its full interaction area. Payload snapshots, drop validation, palette reveal and favorite persistence are unchanged. All six existing native drag regression tests pass (`/private/tmp/heynotes-icon-only-drag-tests.log`). Actual lift/drag appearance remains a physical-iPad acceptance check.

Signed Release compilation succeeded and the updated app installed on the iPad (sequence 3112). Automatic launch was blocked by the device lock; open HeyNotes after unlocking to check the native drag appearance.
