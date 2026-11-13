# Fast page turns and intentional page creation

## Behavior

At fit-to-page zoom with Draw with Finger disabled:

| Gesture | Result |
| --- | --- |
| Short horizontal finger flick left/right | Next/previous existing page |
| Modest slower horizontal swipe | Next/previous existing page |
| Flick left at the last page | Remain on the last page; no new page |
| Pull left beyond the creation threshold and keep the finger down for 0.5 seconds | Save pending ink, add one page and open it |
| Lift early, pull back or lose gesture eligibility | Cancel the creation countdown |

Existing pages track the finger without committing until release. Prepared neighboring paper/ink surfaces move alongside the current sheet and can reverse or cancel before release; a decisive reverse flick cancels even a longer pull. On an accepted release, a prepared sheet immediately continues sliding while saving/loading runs. Validation adopts that same animator without restarting or forcing it to its endpoint. The full travel is the viewport width (or the rendered sheet width when larger) plus a 16-point gutter, using a decelerating cubic curve over 160–240 ms according to gesture velocity and remaining travel. A preview that settles before its load completes stays read-only until validation. Cold destinations without a prepared native canvas still wait for foreground loading. Both scroll viewports retain layout, zoom, coordinates and full opacity; the background stays stationary. Reduce Motion replaces the sheet directly at zero offset and disables interactive movement. Pencil ink pauses until the page is both safely opened and in place. Routine layout passes do not reset a running transition; resizing finishes it cleanly. Failed saves return both sheets to the original page with pending ink intact.

A follow-up finger flick during the incoming animation is accepted into a one-action queue. The destination is prepared immediately. The remaining current motion is retimed to at most 60 ms before the next page is published, avoiding a forced snap to the end. A newer gesture replaces the pending request; page/session/window/gesture guards run again before it executes. Rotation and programmatic replacement clear the queued request.

Sidebar, tabs, palette and editor controls keep their normal colors during short page loads. Pointer hit testing pauses instead of toggling the global disabled appearance; existing service guards continue to reject conflicting navigation/mutations. Actual unavailable actions (first/last-page boundaries, missing pages) retain their ordinary disabled state. This avoids briefly greying and restoring all controls on every turn. Manual VoiceOver review during loading remains part of device acceptance.

Creation alone shows a restrained paper pull plus a temporary progress indicator beside the last page. The indicator is outside the scroll view, cannot intercept writing and is absent during normal editing. The top Add Page button still adds immediately.

## Policy and lifecycle

`PageGesturePolicy.swift` separates classification and timing from UIKit. A flick needs at least 12 points of horizontal travel, at least 350 points/second horizontal release velocity, matching direction and clear horizontal intent. A slower swipe needs 5.5% of viewport width, bounded to 36–52 points. Tiny movements and vertical/diagonal intent are rejected.

Creation requires a leftward pull of 9% of viewport width, bounded to 56–80 points. Velocity alone cannot create a page. `PageCreationHold` measures uninterrupted eligibility using injected monotonic time and emits a single commit after 0.5 seconds. Returning below the threshold resets the countdown. Commit stays latched until a new gesture begins, so releasing after completion cannot add a second page.

`CanvasHost` updates only the progress control while holding, at about 30 updates/second. The task uses weak ownership, is cancelled on gesture end/cancellation, viewport resize, removal from the window, disabled editor state, zoom/finger-count changes or Pencil drawing. The view also checks foreground scene state before creation. Normal page gestures remain direct-touch-only, at minimum zoom, and yield to Draw with Finger. Zoomed dragging remains scrolling.

The callback retains the page UUID rather than the SwiftData object and verifies the current session/canvas identity and enabled state before dispatch. Ordinary turns call `turnPage` with creation disabled; only a completed hold passes explicit creation authorization. `EditorSession` retains flush-before-commit semantics, so failed saves leave the original page and pending drawing intact. `PageLoader` snapshots immutable paths and overlaps loading a different target with the outgoing save; its ink and PDF background loads can also overlap. Opening the same page or another page sharing its drawing path waits until saving finishes to avoid reading an old checkpoint. Cancelled loads never commit metadata. A failed turn retains the original sheet and settles any creation pull. The active page and its neighbors use a bounded decoded-content store and at most two prepared native canvases. See [PagePreparation.md](PagePreparation.md) for version checks, cancellation, memory limits and local Instruments markers. Editor input permission and animation pause are tracked separately so finishing/resizing a transition cannot re-enable Pencil ink during a disabled/save state. New pages inherit paper and dimensions, including blank note pages added after PDF pages. No persistent schema, original PDF, drawing format or file path changes.

## Verification

All 43 native simulator tests passed, including four gesture tests and four load/transition tests plus the existing editor/save/recovery, workspace, PDF, templates, covers, tools, palette and profile suites. New cases cover short flick directions, small/diagonal/reversed rejection, creation-pull intent, timer boundaries, cancellation/restart, one commit per gesture, last-page flick protection and actual pending PencilKit ink saved before a single inherited page is added. Load/transition tests cover same-page reloads with pending ink, a shared legacy drawing path, finger interaction during animation, clean completion when resizing, opaque stationary viewports and zoom/ink coordinate stability while moving the paper surface. Existing save-failure and late-callback tests also pass.

Simulator and signed device builds passed. Automated policy tests use supplied time and do not sleep for the hold duration. They do not synthesize native multitouch or establish physical Pencil latency.

Delivery: the final update installed successfully over the existing Notes app on the connected iPad Air (5th generation). The original bundle identifier, document store and binary file paths were retained. The half-second/no-flash refinement also passed simulator tests and a signed device build. Physical visual/gesture-feel acceptance remains the manual check below.

Manual iPad acceptance: flick through several dense pages in both directions; flick at the final page without creating one; pull left and observe the 0.5-second fill; cancel by lifting early or reversing; complete and keep holding to confirm exactly one page; repeat after handwriting and PDF annotation. Try pinch/zoom, a second finger, Draw with Finger, backgrounding, rotation, tab switches, an injected save failure and Reduce Motion. Confirm the temporary indicator disappears and writing/page order remain intact. Adjust gesture feel only from measured hardware feedback.

## Full-sheet slide refinement — 2026-11-12

PageCanvasContainer now owns transition lifecycle in its own component file. PageTurnMotion contains deterministic distance, timing and edge-resistance policy. Existing-page pulls track finger translation; first/last-page edges use a bounded 24-point resistance. Cancelled pulls return with a short critically damped animation. Touch movement operates on pageSurface, with the scroll contentOffset retained. No snapshots or PKDrawing rasterization are introduced in production.

The original short-flick thresholds and 0.5-second new-page hold remain in use. Loading a destination still crosses the existing save boundary; page IDs, source PDF files, drawing paths and autosave semantics are unchanged. The preceding compact-menu work remains in the local working tree. No commit or push is performed for this refinement.

New tests also check programmatic navigation from a zoomed sheet clears the outgoing paper completely. They cover gesture tracking, symmetric/bounded velocity timing, preserving a drag position into full-width motion, one queued follow-up, resize cancellation, Reduce Motion replacement and native mid-transition captures in both directions. The viewport frames, opacity, zoom, content size and drawing remain stable. Automated checks establish geometry/lifecycle behavior, not physical display FPS or a subjective smoothness guarantee. Review rapid repeated flicks, handwriting-heavy and PDF pages, a cancelled pull, rotation, zoom, Reduce Motion and the last-page hold on the iPad.
