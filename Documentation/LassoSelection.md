# Mixed-content lasso selection

## Behavior

The previous lasso was exclusively `PKLassoTool`: it could select editable strokes inside `PKCanvasView`, but inserted text, converted handwriting, shapes, images, study tape and sticky notes live in a separate object layer. A loop around both layers therefore left objects behind.

The lasso now defaults to **All Content**:

- On pages with inserted objects, a closed Pencil loop selects whole visible strokes and intersecting/enclosed objects together. A small zoom-adjusted tolerance includes ink touching the loop, including wide marker edges. The path closes automatically when lifting.
- The selection outline covers the resulting group. Drag inside it with Pencil or a finger to translate the group while preserving relative positions and permanent object IDs. Movement is clamped as one group to the page bounds. Folded notes use their visible header for selection and their complete rectangle for safe movement.
- Tap inside the selection for **Delete** or **Deselect**. Move/delete uses one compound Undo/Redo action for both ink and objects. Cancelling a gesture or leaving/backgrounding clears the preview without changing the committed page.
- On pages containing only ink, PencilKit's native lasso remains in use automatically, retaining its existing copy/paste/resize behavior.
- Select Lasso again or open its settings and choose **Handwriting Only** to use the native ink lasso on a mixed page. This scope keeps inserted objects separate. All Content currently supports group movement/deletion; native ink editing remains available through Handwriting Only. Converted text is selected as a complete text object/line, not as individual characters.
- At full-page zoom, a horizontal finger flick outside the selected group still turns pages. A finger drag inside the group moves it. Two fingers pan/zoom in mixed selection mode; Draw with Finger also allows drawing the loop with a finger.

The original PDF content and paper template remain backgrounds. They are not moved or removed by the lasso; imported-document annotations and added content remain independently editable.

## Geometry and compatibility

`PageLassoSelection` builds an immutable selection from a drawing/object snapshot. It tests the actual closed polygon rather than only its bounding rectangle, preserving concave exclusions. Stroke hit testing uses interpolated visible masked ranges, the stroke transform and sampled width. Erased/invisible ranges do not create a selection. Shape outlines use their paths; text/image/note/tape bounds represent the complete object. An item's selection never changes its stored ID.

`PageLassoOverlay` renders selected/remaining ink once on a background task and reuses the bounded images during movement. Object text uses a per-view Core Text layout cache. Source ink rendering explicitly uses a light trait environment, matching the paper canvas in Dark Mode. The native drawing and document elements remain untouched throughout preview: only its presentation is temporarily replaced. A navigation/export/background flush cannot accidentally save an ink subset or an uncommitted drag.

Committing a movement/deletion rechecks the current page ID, native canvas, complete drawing and object values, readiness, busy/export state and closed Zoom Writing window. Stale results are rejected and the activity guard is released. Zoom Writing closes before entering the lasso. Native stroke/page navigation guards and actual-canvas flushing remain in place.

Worker tasks cancel when a newer loop begins, the scope/tool changes, the view leaves its window, the app resigns active or a canvas is retired for page navigation. Page/finger navigation waits for an in-progress selection calculation/drag, but remains available around an idle selection. Canvas identity and UndoManager are retained.

The current deployment target remains iPadOS 17. No iPadOS 27 selection APIs, private PencilKit views, recognizer introspection or document migrations are used. The native scope uses the existing public `PKLassoTool`; the mixed overlay uses public PencilKit model values and UIKit gestures/edit menus. `UIEditMenuInteractionDelegate` is bridged with `@preconcurrency` because its legacy Objective-C protocol lacks actor annotations; UIKit delivers this view-owned menu interaction on the UI thread.

## Preferences and persistence

`LassoScope` is an optional addition to the existing `editor.tools.v1` preferences and `ToolPreset` JSON. Older preferences/presets default to All Content without losing other settings. Palette favorites retain and compare their selected scope.

Mixed edits use the existing compound ink/object command and autosave pipeline. There are no new SwiftData tables, file formats, stroke flattening or permanent selection indices. Selection membership and preview images are transient. A text object's original-ink anchors, custom-font paths, embedded source data and image references are preserved during movement. Existing recovery/source archives are retained.

## Verification

Native tests cover mixed object kinds and transformed ink, marker-edge/crossing hits, masked ink, concave loops, folded-note visibility, unfilled shape interiors and group clamping. The actual SwiftUI editor is exercised for mixed selection, one-step movement/delete Undo/Redo, stable IDs, editable drawing/object persistence, cancellation/background flush, stale/busy rejection, releasing pending calculation guards, scope persistence/presets, native pure-ink fallback and tool switching. Actual selected-content screenshots are inspected. Existing editor, handwriting, page gestures, modal sizing, palette, toolbar placement and fluidity regressions are included in the selected run recorded in [Validation.md](Validation.md).

These tests invoke the real geometry and native control handlers but do not synthesize physical Apple Pencil contact. Physical acceptance should include an imperfect loop around a mixture of ink/converted text/images/shapes/notes, moving at multiple zoom levels, fast repeat selections, eraser masks, original-ink restoration after group movement, long native ink menus, Undo/Redo, relaunch and both orientations. Installation remains deferred at the owner's request.

## Apple references

- [PKLassoTool](https://developer.apple.com/documentation/pencilkit/pklassotool-swift.struct)
- [UIEditMenuInteraction](https://developer.apple.com/documentation/uikit/uieditmenuinteraction)
- [Presenting an edit menu](https://developer.apple.com/documentation/uikit/uieditmenuinteraction/presenteditmenu(with:))
