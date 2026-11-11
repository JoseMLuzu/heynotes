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
