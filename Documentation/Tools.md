# Expanded drawing tools

## Interaction

The compact toolbar now includes pen, pencil, highlighter, eraser and lasso. Tap once to select a tool. Tap the selected tool again, touch and hold it and choose Tool Settings, or tap the controls button next to the color/width summary to open its options. A scrollable popover keeps additional controls off the handwriting canvas. Changes apply immediately; Done closes the panel.

## Ink options

Pen, pencil and highlighter each retain independent width, RGB color and opacity. Width sliders respect PencilKit's public native validWidthRange, capped at 12 points for pen/pencil and 60 for highlighter. Preset buttons offer common values within that tool's range. Sizes are actual nominal PencilKit widths; highlighter width is no longer an implicit multiple of the pen width.

There are 12 named palette colors plus the system custom color picker. Opacity is adjustable from 10% to 100%. The curve preview approximates color, opacity and nominal width; pressure, tilt and PencilKit's textured rendering still affect real strokes. Preview width is visually capped at 36 points. Each tool can be reset independently.

## Eraser

- Whole Strokes uses native PKEraserTool(.vector). Touching ink removes the entire stroke; there is no misleading size control for this mode.
- Precise uses native PKEraserTool(.fixedWidthBitmap, width:). It removes only touched portions at a fixed size. Its size slider/presets respect the native width range, capped at 100 points. This public API is available from iPadOS 16.4, below the app's iPadOS 17 minimum.
- Clear Page Handwriting requires confirmation and only clears the ink layer. It preserves page records, paper templates and PDF backgrounds. The action participates in the current canvas's undo/redo history and the existing automatic save pipeline. As with all editor undo history, leaving the page ends that session's undo history.

Lasso continues to use native PencilKit selection. Its panel explains selection/movement instead of advertising unsupported custom selection filters or handwriting conversion.

## Persistence and safety

ToolPreferences stores a small versioned JSON preference value in local UserDefaults, separately from SwiftData and document files. Reopening a notebook/app restores the selected tool and independent ink/eraser settings. Invalid stored numeric values are clamped before constructing native tools; unreadable preference data falls back to defaults. No notebook schema change is needed.

The clear action registers its prior PKDrawing with the canvas undo manager. Undo and redo update the session snapshot and trigger the same debounced save flow as drawing. Page identity guards prevent callbacks or undo actions from applying ink to another page.

## Files and verification

- `Features/Editor/Services/ToolPreferences.swift`: tool construction, validation and local preferences.
- `Features/Editor/Components/ToolOptionsPanel.swift`: ink palette, sliders, presets, preview and eraser controls.
- `Features/Editor/Views/EditorView.swift`: compact toolbar and settings presentation.
- `Features/Editor/Services/EditorSession.swift`: undoable clear-handwriting operation.
- `NotesAppDeviceTests/ToolPreferencesTests.swift`: independent preference restoration, native eraser mode/width construction and clear/undo/redo/save behavior.

All 12 native tests passed on the iPad Air simulator (the existing 9 editor/PDF tests plus 3 tool tests). A simulator app build also passed. Actual Pencil pressure, partial erasing gestures and panel layout at large text sizes require hardware review.

## Manual checks

1. Change color, width and opacity for pen, pencil and highlighter; switch between them and relaunch to verify independence and restoration.
2. Try palette colors and a custom color, including in dark mode. Check selection rings, VoiceOver labels and width readouts.
3. Erase the same type of stroke using Whole Strokes and Precise at multiple sizes. Confirm undo/redo restores native eraser edits.
4. On a disposable test page, clear handwriting, cancel first, then confirm. Undo, redo, switch pages and relaunch. PDF/paper backgrounds must stay unchanged.
5. Open settings through a second tap, the controls button and the context menu. Check portrait/landscape, narrow windows and larger Dynamic Type; the options scroll without expanding the editor toolbar.

Reference: [Apple PencilKit eraser API](https://developer.apple.com/documentation/pencilkit/pkerasertoolreference).

Device delivery: the signed iOS device build passed. Installation was attempted on the paired iPad, but CoreDevice rejected developer-disk mounting because the physical device was locked (error 10003). The tool changes were subsequently installed with the optimization build; see Performance.md for the latest delivery status.

## Stable width readout — 2026-11-09

The editor's stroke-width readout reserves a localized two-digit/one-decimal text slot using the same monospaced caption font. Integer and decimal values retain their compact formatting while the settings button, neighboring controls and popover anchor keep a constant width. The invisible sizing text is excluded from accessibility. The slot follows Dynamic Type rather than relying on a fixed point width. Signed iPad device build passed.

## Local save indicator — 2026-11-09

The toolbar's checkmark Save button is replaced by a 7-point blue/orange status dot at the far right of the editor header. It is not a tool or a button. Orange covers pending/active writes and failure; blue follows a successful current-revision save. VoiceOver exposes actual save status. Save Now is available in Page Options and the drawing error alert provides Retry Saving. No cloud sync is implied. The bookmark button now directly toggles the current page; the index retains bookmark browsing/renaming.

## Contextual quick adjustments — 2026-11-09

Spare toolbar width now holds three customizable favorite colors and three width presets, eraser mode/size shortcuts, or edit/duplicate/delete for the selected inserted object. Narrow windows expose the same row from the toolbar ellipsis before the palette. See QuickAdjustments.md for use, local preference compatibility, object-copy/undo semantics and validation.
