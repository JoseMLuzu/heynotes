# Toolbar placement

## User workflow

Open **Page Options (ellipsis) → Toolbar Position** and select **Top**, **Bottom**, **Left** or **Right**. The selected item is checked. The preference is saved locally and reused across documents and app launches. Top remains the default; unknown stored values safely fall back to Top.

Top and Bottom use a horizontal strip with inline quick adjustments when space permits. Left and Right use a 52-point vertical capsule, centered below the navigation header, capped at 620 points high. Short windows scroll the primary tools vertically; Quick Adjustments and Quick Palette remain pinned at the end. The vertical settings button uses a compact icon, with the full settings available in its popover. Tool controls keep their 44-point targets and immediate-touch behavior.

Back, tabs, sidebar, Undo/Redo, bookmarks, page index and Page Options remain at the top. The independent floating Quick Palette remains movable within the available canvas area. This feature docks the main toolbar to one of four edges; it does not introduce unrestricted dragging of the entire toolbar.

## Implementation

- `EditorToolbarPreferences.swift`: four valid positions and a separate UserDefaults key (`editor.toolbar.position.v1`). No SwiftData model changes or migration.
- `EditorToolbar.swift`: the existing working controls extracted into one reusable horizontal/vertical component. There is one live control tree and one source per popover.
- `EditorView.swift`: a stable chain of safe-area insets reserves room for the selected edge. Navigation remains outside the side rails. The canvas stays in the same structural position; moving tools does not replace PKCanvasView or reset its Undo manager. Left/Right placement is mapped to the correct physical side for the layout direction.
- `ToolbarQuickControls.swift`: an optional popover arrow edge supports inward-facing quick adjustments from each dock.

The native glass background remains separate from interactive foreground controls, preserving the previous dropdown fix. Side/bottom inset backgrounds match the canvas surround. No global UIScrollView settings, page IDs, ink bytes, object positions or notebook timestamps are changed by a placement preference.

During validation, the shared object renderer's system-font fallback was corrected to create a system CTFont directly. Passing UIKit's private system font name to `CTFontCreateWithName` could substitute Times New Roman. Named handwriting fonts continue to use their installed public font names.

## Verification — 2026-11-10

- All 63 native tests pass after the toolbar extraction and placement implementation.
- The two placement tests pass again after the final rail-height/background refinement.
- Tests cover all persisted positions, invalid-preference fallback, symbol availability, all four edges in portrait/landscape, unchanged canvas identity, preserved ink and a functional Undo action after repositioning.
- Eight native screenshots were exported and inspected. Layout tests use actual SwiftUI editor views and PencilKit canvases.
- These tests do not inject physical taps into native menus or measure real Pencil latency. Physical menu selection and writing remain device acceptance checks.

## Device acceptance

1. Select each edge from Page Options. Check the selected menu item and reopen a different notebook/app session to confirm persistence.
2. Select tools, open settings, shapes, Insert and Quick Adjustments at every edge. Dismiss popovers by tapping outside.
3. Write, reposition the toolbar, Undo/Redo, turn a page and return. Confirm all ink and editing history behave correctly.
4. Rotate, resize to a short window, pinch to zoom and scroll. The rail must remain reachable, and the page must not sit beneath the dock.
5. Repeat with Dark Mode, Reduce Motion, Reduce Transparency and VoiceOver.

The final signed device build and installation on the connected iPad Air (iPadOS 26.5) succeeded. Existing application data was retained. Final side-rail background and compact-height screenshots were also inspected.
