# Editor toolbar presentation and touch response

## Changes

The shared editor glass surface now renders its material in a separate, noninteractive background. The buttons, menu sources and popover anchors are foreground content. A menu lifting its source therefore does not intentionally promote the whole toolbar into the preview. Native iPadOS 26 glass remains available; earlier supported releases retain regular material, and Reduce Transparency retains an opaque surface. The toolbar no longer clips the complete interactive control tree to a capsule.

Primary tool selection updates immediately. The previous 180 ms selection animation and matched-geometry highlight were removed. Primary tools no longer install a redundant long-press context menu: tapping the active tool or its settings readout still opens Tool Settings. Buttons get immediate touch-down feedback and a 90 ms release animation, disabled under Reduce Motion. Tool changes are not wrapped in an animation transaction that reaches the canvas.

A measured strip uses a plain row when all controls fit. Only narrow windows use horizontal scrolling. There is exactly one live control tree, so each popover has a single source anchor; alternative measured copies of the same popover controls are not retained. Existing width reservations for quick adjustments and the palette are preserved.

The overflow row contains a small UIKit probe. Using public UIView hierarchy traversal, it configures only the nearest enclosing UIScrollView with `delaysContentTouches = false` and `canCancelContentTouches = true`. This removes the default touch-down wait while retaining cancellation into a horizontal drag. It never changes the app-wide UIScrollView appearance or the PencilKit/page scroll view. If SwiftUI changes its wrapper hierarchy, the scoped policy may need revisiting; native tests verify the actual installed hierarchy.

No notebook models, saved strokes, file paths, Undo history or document persistence were changed.

## Validation — 2026-11-10

- Simulator build succeeds.
- All 61 native tests passed after the initial toolbar changes.
- After the final single-anchor layout adjustment, all five targeted toolbar, quick-control and editor-opening tests passed.
- Native screenshots at 720, 1024 and 1366 points were exported and inspected.
- Tests verify that overflow receives immediate-touch settings, its enclosing page scroll view is untouched, and the same PKCanvasView survives window resizing.

These tests do not inject physical taps into UIKit menu presentations and do not measure end-to-end input latency. Actual dropdown visibility and perceived response require acceptance on the physical iPad. No unsupported gesture injection or private API is used.

## Device acceptance

1. Reopen the updated app. Tap Pen, Pencil, Highlighter and Eraser repeatedly; selection should update promptly. Tap the active tool to open settings.
2. Open Shapes, Insert, Quick Adjustments and Page Options. The toolbar should remain visible behind the presentation. Dismiss by tapping outside and repeat.
3. In a narrow window, swipe the tool strip horizontally. Confirm taps still work and dragging does not accidentally select tools.
4. Write with Pencil, switch tools, Undo/Redo, turn pages and resize/rotate. Confirm ink and canvas state are preserved.
5. Repeat with Reduce Motion, Reduce Transparency, Dark Mode and VoiceOver.

## Apple API references

- [UIScrollView.delaysContentTouches](https://developer.apple.com/documentation/uikit/uiscrollview/delayscontenttouches)
- [UIScrollView.canCancelContentTouches](https://developer.apple.com/documentation/uikit/uiscrollview/cancancelcontenttouches)
- [SwiftUI glassEffect](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))

The final signed device build and installation on the connected iPad Air succeeded. Existing app data was preserved.

## Top ellipsis activation — 2026-11-10

A second user report identified the Page Options ellipsis beside the document tabs. Previously `DocumentTabBar` applied `allowsHitTesting(!workspace.blocksNavigation)` to its entire row. That predicate includes UIKit's drawing recognizer state, which is not observable by SwiftUI. Rendering the row during a stroke could therefore leave Page Options untappable until an unrelated observed update rebuilt the row.

The row now gates only on observable document switching/page-operation state (`blocksTabControls`). Actual navigation still checks the live stroke state at action time: tab open/close already do so in the workspace, and sidebar/Library actions now do so explicitly. Opening Page Options does not navigate or replace the canvas.

`EditorMoreButton` is a native UIButton with a full 44 × 44-point area, accessibility label/identifier, current-action updates and explicit cleanup. The top button uses `showsMenuAsPrimaryAction` with a prebuilt UIMenu from `EditorPageMenu`. All prior Page Options commands, checkmarks, disabled/destructive states, document operations and confirmation flows are retained. The Quick Adjustments ellipsis uses the same native control to present its existing popover. The palette's decorative border no longer intercepts touches, and its menu label explicitly covers its 44-point square.

All 66 native tests pass, and the signed device build succeeds. Three new tests verify a single native activation opening the actual Quick Adjustments popover, border-area hit testing, current/disabled callbacks, and the actual tab-strip Page Options control remaining hit-testable with a simulated active recognizer while workspace navigation remains protected. They also exercise the native menu's toolbar-position action. These checks exercise UIKit controls and presentation, but do not inject physical finger events or establish end-to-end menu-opening latency on hardware.

## Tool organization — November 14, 2026

The toolbar now gives the expanded tools permanent icon groups instead of placing them in Insert's nested menus:

- Writing and selection remain direct buttons on the left: Pen, Pencil, Highlighter, Eraser, Lasso and Select Objects.
- **Draw** opens a labeled grid for Line, Rectangle, Ellipse, Arrow, Protractor and Compass, plus Ruler and Hold to Snap Shapes switches.
- **Study** opens Study Tape, Sticky Note, Stamp and Region Flashcard.
- **Capture** opens Region Capture and PDF Text Highlight. The latter is visibly disabled on ordinary notebook pages.
- **Laser** and **Zoom** have direct icon buttons. Zoom remains visibly active while its writing window is open; tapping it closes the window after a successful save.
- **Insert** contains handwriting style, typed text, Photos/Files images and editing inserted content. Expanded tools are no longer duplicated there.
- Color/width settings sit after the tools, followed by direct favorite colors/width presets as space allows and Quick Palette. The readout reserves a constant width for all tool names and decimal stroke widths. Direct adjustments can show all three eraser modes, including Highlighter Only, with size controls for both fixed-size erasers. All settings remain available from the settings button.

The three toolbar groups show icons only, retaining full VoiceOver names and hover help. Their anchored native popovers retain labeled tiles. Merely opening a group preserves the selected tool; choosing a tile closes its group and immediately selects that tool. Tapping the separate settings control edits its style. Only one group presentation can be active. No notebook metadata or ink files change when browsing these controls.

`EditorHeaderLayout` places the same back, toolbar and page-action control trees in its first layout pass. Wider windows retain a single row; narrower/portrait or split panes place the toolbar on a full-width second row. It does not measure into State and then swap duplicate toolbars, which avoids an initial layout jump and duplicate popover anchors. Side/bottom placements remain supported; overflow scrolling is retained for genuinely small windows. Undo, redo, bookmark and page-index controls remain together in the page-action capsule.

New code: `ToolbarToolGroup.swift` contains tool homes, availability and tile presentation; `EditorHeaderLayout.swift` contains adaptive placement. Existing `EditorToolbar` and `EditorView` compose those components. No storage migration, new dependencies, commit or push is included.

Validation for this organization change: 24 native tests covering expanded tools, palette/adjustment activation, toolbar placement and resizing passed before adaptive-header refinement. The adaptive header then passed the targeted navigation, toolbar, placement, native-button and new organization suites. New tests require every EditorTool to have exactly one toolbar home, keep PDF-only availability contextual, and verify that group/tool changes preserve the same native canvas, inserted content and Undo history. Screenshots were inspected for the three tool grids and the complete editor at 1180 and 820 points. In portrait the second row shows Draw, Study, Capture, Laser, Zoom and Insert together. Signed Release compilation succeeds. Physical touch feel remains a device acceptance check.

## Compact adjustments refinement

Visible toolbar captions (Draw, Study, Capture, Laser, Zoom and Insert) are removed. The group grid titles/tool names and accessibility labels remain. The Quick Adjustments ellipsis and its separate overflow popover are removed from both horizontal and vertical toolbars; Page Options beside the tabs/page controls remains a separate navigation action.

The current-color/width/settings button uses an 88-point horizontal footprint with a stable 32-point numeric column. It no longer spreads its contents across an expanding readout or displays a tool-name placeholder. Spare width now shows direct favorite colors first, then width presets; the eraser shows mode/size choices and object selection shows edit/duplicate/delete as space permits. Every control retains a 44-point hit area. The single row grows from zero to six adjustment controls without hiding the primary tools to make room. Favorite colors retain their customize context menus.

The glass capsule hugs actual tool/control content rather than filling a reserved blank lane. Very narrow windows retain native tool scrolling and the full settings button; vertical placement keeps the compact settings control. No toolbar ellipsis is rendered. The obsolete native overflow-popover activation test was removed because that button no longer exists; general native Page Options/button tests remain.
