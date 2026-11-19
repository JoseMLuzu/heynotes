# High-zoom ink and converted text

## Problem

The editor's outer UIScrollView magnified the page while the nested PKCanvasView remained at its default native zoom. Converted handwriting and other inserted objects shared one full-page UIView bitmap capped to 2400 pixels on the longest side. Enlarging those surfaces made small writing look soft. Increasing the entire page's bitmap scale would be especially expensive for large PDF pages.

## Rendering

`InkCanvas.synchronizeViewport` gives PencilKit the actual magnification and maintains an inverse view transform so editable strokes keep their original logical page coordinates. Its native bounds cover a buffered visible region, with each backing dimension limited to 4096 display pixels. Panning inside the buffer does not reconfigure it. Both the main editor and Zoom Writing use this path. Shape-hold input converts native view points back to page coordinates; its preview applies the matching native scale.

A programmatic zoom of the nested non-scrolling canvas did not reliably repaint previously rendered ink in the simulator. After PencilKit's first render completion, coalesced refreshes reuse the exact existing PKDrawing. They do not rebuild strokes, encode data, create undo entries or call the session's save operation. The editor's existing equality guard rejects unchanged drawing callbacks. Refresh waits for an active Pencil gesture to end and is cancelled when the canvas leaves its window. Prepared canvases receive render completions too.

Native ink-only lasso uses a stable full-page surface while selected, capped to 2400 display pixels on the longest side. Entering this mode configures the surface once; subsequent zoom/pan does not replace its drawing or clear its transient selection. Leaving it restores the writing viewport's resolution. Mixed-content lasso remains on its existing page-coordinate overlay.

`PageObjectsContentView` uses `PageObjectsTileLayer` (CATiledLayer). Visible 512 × 512 pixel tiles redraw text and vector objects at magnification, with detail levels through 8× and no tile fade. Background drawing receives a locked snapshot of value elements and retained images. A separate lock serializes access to the bounded Core Text layout cache. Background callbacks never access UIView state or SwiftData. Tiles include stroke/arrow padding at clip boundaries. Study tape remains on the upper interaction layer, preserving its order above ink.

## Pinch regression correction

Physical feedback after the first installation exposed a gesture regression that the original programmatic zoom tests did not cover. Setting PencilKit's native zoom range also made its own pinch recognizer eligible to compete with the outer page. InkCanvas now disables its native navigation recognizers after initialization/layout and rejects those recognizers through UIView's public gestureRecognizerShouldBegin method. The actual drawing recognizer continues through PencilKit's normal handling. Only the page owns finger zoom/pan.

During a user pinch, native viewport reconfiguration and cached-drawing refresh are suspended. The outer page handles the gesture continuously; native resolution catches up after release. The same policy applies to Zoom Writing.

The page's old layout logic also snapped any zoom within 0.01 of its fitted minimum back to that minimum. Frequent layouts could therefore cancel the small first increments of a real pinch. Fitting now occurs at initial layout or when the viewport changes size while already fitted, and never during active/bouncing zoom. A dedicated test covers 0.002/0.004/0.008/0.02 initial zoom increments. The public accessibility value exposes the current zoom percentage.

Real XCUI pinch/pan tests complement the native rendering tests: they create a separate notebook through the UI, select a writing tool, cumulatively zoom, change tools, pan and draw a small editable finger stroke. They do not synthesize Apple Pencil contact or establish physical-device sharpness.

Reference: [UIView gestureRecognizerShouldBegin](https://developer.apple.com/documentation/uikit/uiview/gesturerecognizershouldbegin(_:)).

## Data and scope

There is no schema, drawing file format, page ID, source archive or export geometry change. The high-resolution text path also covers imported fonts through the existing registration/cache preparation. Source drawing data remains editable.

This changes on-screen ink and inserted/converted text. The paper/PDF background preview and temporary mixed-lasso raster preview retain their previous resolution limits. It does not add vector PDF background tiling or recover detail missing from a scanned PDF. Tiles and PencilKit render asynchronously; this is not a guarantee that every intermediate pinch frame is already at its final detail level. The dimension limits are not a measurement or total cap on process RAM.

## Verification

Six `ZoomRenderingTests` cover:

- Existing ink rendering again after immediate high zoom, including an initial render still in flight.
- Saved drawing equality, unchanged edit date/file bytes and no pending autosave after zoom, followed by compound ink/text Undo and Redo.
- Logical page/touch coordinates across zoom, pan and zoom-out.
- A 14400 × 14400-point page's bounded viewport and full-page native lasso reachability.
- Zoom Writing's resolution, render completion and coordinates.
- Small handwriting text at 8× matching a direct high-resolution render, differing from an enlarged bitmap, and invalidating its cached text after an edit.

The final selected native run passed 72 cases, including editor persistence/recovery, page gestures/animations, mixed lasso, expanded student tools, handwriting placement/imported fonts, fluidity and PDF export. Signed Release compilation passed. Physical Pencil feel, peak memory and the oldest supported iPadOS runtime still require device acceptance. No physical install was attempted in this pass.

The diagnostic simulator compositor capture showed both existing native ink and converted text at 4×. UIView hierarchy snapshots alone omit PencilKit's Metal-rendered ink, so they were not used as evidence that native ink was missing or sharp. See Validation.md for logs and result bundle.

Apple references: [PKCanvasView](https://developer.apple.com/documentation/pencilkit/pkcanvasview), [render completion delegate](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdelegate/canvasviewdidfinishrendering(_:)), [UIScrollView zoomScale](https://developer.apple.com/documentation/uikit/uiscrollview/zoomscale), [CATiledLayer](https://developer.apple.com/documentation/quartzcore/catiledlayer). The implementation uses public APIs available at the iPadOS 17 deployment target; it introduces no iPadOS 27-only API.
