# Performance pass — editor, previews and saving

## Findings and implementation

1. **PDF reopen/rerender on every visit.** PDFDocumentService now keeps actor-confined, fingerprinted PDFDocument and image LRU caches. The editor pool retains at most two documents and 24 MiB of image buffers. File path, size, modification date and inode identify the source version. A source is checked before cache lookup, so missing/replaced/corrupt files cannot be hidden by an old cached image.
2. **Gallery work sharing the editor's render queue.** PDF thumbnails use a separate worker actor, one retained PDFDocument and a 4 MiB image pool. Composited page thumbnails use a separate utility-priority actor and a 4 MiB/128-entry cache. Opening/reusing the gallery avoids repeated decoding of unchanged ink. Cancellation is checked before and after rendering and before applying a result to a SwiftUI thumbnail.
3. **Thumbnail resolution growing with document coordinates.** Composite thumbnails are limited to 180 pixels on their longest side, including for a 14400 × 14400 logical-point PDF page. Previously, the 0.15 ink scale produced a 2160 × 2160 raster for that case. The new output has 144× fewer pixels for that particular extreme size; this is a raster-size comparison, not an app-wide RAM measurement. Regular note thumbnails retain comparable display resolution.
4. **Background view backing stores scaling with very large page coordinates.** The paper UIView backing scale is capped to 2400 pixels on its longest side. Logical page/ink coordinates and export geometry remain unchanged. Very large pages can fit the viewport at less than 10% zoom. This was the original optimization; the later [high-zoom rendering pass](ZoomRendering.md) now supplies PencilKit with a bounded native viewport at the actual writing zoom and renders inserted text with tiles.
5. **Saving repeatedly while new ink arrived during a write.** Debounced autosave now writes one immutable checkpoint after the pause. Explicit navigation, background and export flushes wait for existing writes and keep draining newer revisions before returning. There is still only one in-flight save task. Drawing snapshots and UIKit canvas references are excluded from SwiftUI Observation; the visible dirty status only changes when needed.
6. **Backup copies allocating a second complete drawing Data buffer.** Checkpoints now copy file-to-file into a unique sibling staging file, then atomically replace/move the backup before atomically writing the live drawing. Tests exercise repeated backup replacement and restoration. This avoids explicitly allocating the previous drawing as another Data value; filesystem copy behavior is system-controlled.
7. **Unnecessary UIKit updates and sorting.** Equivalent tools are not reassigned to PKCanvasView, unchanged templates do not trigger paper redraw, identical zoom/inset values are not reapplied, and common navigation avoids repeatedly sorting the same page relationship for first/last checks.

The two PDF image pools plus composite-thumbnail cache have a combined 32 MiB image-retention budget. This is not a hard cap on total app memory: visible views, transition canvases, PDF internals, drawing data and active render buffers also consume memory. Memory-warning handling releases reusable caches without removing documents or pending ink. PDF export still uses original source content and its existing per-page autorelease pools.

## Measurement

A fixed test creates a 768 × 1086-point PDF containing 70 text lines and issues six identical 2400-pixel preview requests to a fresh PDFDocumentService. Import time and PDF generation are outside the timed section. Both runs used the same iPad Air 11-inch simulator and Debug configuration.

| Workload | Before | After |
| --- | ---: | ---: |
| Six repeated preview requests | 17.184 ms | 8.537 ms |
| PDF opens for those requests | 6 (original code path) | 1 (asserted) |
| Preview renders for those requests | 6 (original code path) | 1 (asserted) |

An earlier optimized run measured 8.146 ms. These are local simulator samples, not statistically established hardware speedups, Pencil latency measurements or frame-rate claims. Cold page rendering is still required. Unique pages/files do not benefit from repeat-page hits, and tiny images/sources may make cache lookup overhead proportionally larger.

Logs used during development: `/private/tmp/notesapp-perf-baseline.log` and `/private/tmp/notesapp-optimization-final-tests.log`. XCTest also stores a timing attachment in its result bundle. Reproduce using the NotesApp scheme and the PerformanceTests class; no external benchmark dependencies are required.

## Verification

- PASS: 13 host tests, including byte/count-bounded LRU eviction, repeated checkpoint backup replacement, migration, ordering and existing persistence tests.
- PASS: 17 native tests, including cache reuse/budgets/clearing, replaced/missing PDF rejection, huge thumbnail pixel bounds, missing ink rejection, concurrent flushes retaining the newest drawing and debounce coalescing into one checkpoint. Existing PDF geometry/export and tool/undo tests still pass.
- No schema or storage-path changes were introduced by this pass.

## Hardware review still required

Use a physical iPad and Instruments (Time Profiler, Allocations and animation/frame diagnostics) with a dense handwritten notebook and a long lecture PDF. Check rapid page turns, gallery scrolling, long strokes, background/resume and export. Simulate memory pressure and verify revisiting pages rebuilds caches without losing ink. Compare warm and cold runs separately; collect multiple samples and peak memory rather than inferring overall responsiveness from the small repeated-preview test.

References: [Apple: reducing memory use](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use), [responding to memory warnings](https://developer.apple.com/documentation/uikit/responding-to-memory-warnings).

Delivery: the signed iOS device build passed and the optimized update installed successfully over the existing Notes app on the paired iPad Air. This build also includes the expanded tool settings whose earlier delivery had been blocked while the device was locked.


## Follow-up — 2026-11-10

See [Fluidity.md](Fluidity.md) for granular tool observation, isolated canvas updates, per-view text layouts, conditional overlay redraws, background rich-content decoding, immediate library feedback and the measured repeat-render workload.

## Study and immutable-file preparation — November 16, 2026

The Study dashboard previously refiltered all cards for each deck and sorted due cards repeatedly just to display counts. `StudyOverview` now builds per-deck/global counts, the next date and notebook-title lookup in one pass, then sorts the one global due list using copied date values rather than repeatedly invoking SwiftData getters in the comparator. It is a fresh render-time value, not a stored cache requiring invalidation after reviews/edits/Trash. Existing scheduling, due ordering and calendar-day semantics are preserved.

Captured Study images previously used `UIImage(data:)` from the view's main-actor task, leaving full-size decoding to display. `StudyImageLoader` now decodes/downsamples with ImageIO on a dedicated actor and reuses a fingerprinted LRU cache capped at 16 MiB/32 entries. Decoding is immediate before publishing the image. Review previews request up to 900 logical points times display scale; form previews use 500 points; both are capped at 2400 pixels. Original image bytes and export resolution are unchanged. The cache's source checks reject missing/replaced files, cancellation prevents obsolete publication, and the task identity includes source storage and resolution so a reused view cannot briefly show another card/storage's old image. The app's existing memory-warning path clears this cache too. This is an additional cache budget, not a limit or measurement of total process RAM; live images and decoder buffers are separate.

ImageIO background decoding follows Apple's [image and graphics guidance](https://devstreaming-cdn.apple.com/videos/wwdc/2018/219mybpx95zm9x/219/219_image_and_graphics_best_practices.pdf). Decode itself is synchronous on the worker actor; cancellation is checked before/after it, not claimed to interrupt an ImageIO call mid-decode.

Immutable upload preparation also recognizes repeated references to the same captured descriptor. It copies/hashes that source once and reuses its verified descriptor for other roles. Different source files still require reading before content equality is known. A regression fixture with four asset roles/three distinct captured files asserts three complete read passes, while retaining separate image roles and all integrity/revision/cleanup behavior.

### Local measurements

Both paths were exercised in the same Debug simulator run on the iPad Pro 13-inch (M5), iPadOS 26.5. These are specific local samples, not device FPS, Pencil latency, total app RAM or statistically established speedups.

| Workload | Prior path | Optimized path |
| --- | ---: | ---: |
| Study overview, 60 decks / 2,400 cards, three passes | 1,486.531 ms | 17.533 ms |
| Three displays of a 2400 × 1800 PNG at 900 × 675 pixels | 26.095 ms | 14.894 ms |

The image test forces equivalent-size bitmap drawing in both paths; the optimized service performs one decode and two cache hits, with zero decode blocks sampled on the main thread. The prior overview-only baseline measured 1,422.575 ms in a separate run, illustrating normal run-to-run variability. No timing threshold is asserted. Equivalent counts, source preservation, cache budgets and decode counts are assertions.

Validation: **64 host tests** and **15 selected native tests** passed, including DST/day boundaries, read-only overview queries, reviews/Trash changes, missing/replaced/corrupt images, separate storage roots, cancellation, cache clearing, source-copy integrity, existing PDF cache workloads and native two-editor upload preparation. Logs: `/private/tmp/heynotes-optimization-host-tests.log`, `/private/tmp/heynotes-optimization-native-tests.log`; native result `Test-NotesApp-2026.11.16_02-57-55--0500.xcresult`. Signed Release compilation passed (`/private/tmp/heynotes-optimization-release.log`). The earlier full-suite UI selector failures remain documented separately; this targeted pass does not claim they are resolved. No new metadata schema or file format was introduced by this optimization pass.


## High-zoom writing — November 16, 2026

Both native ink and converted handwriting now use resolution appropriate to magnification. PencilKit uses a buffered viewport rather than allocating a high-resolution full-page canvas; inserted text/vector objects use visible CATiledLayer tiles. Logical coordinates, editable drawing data and export geometry remain unchanged. The native lasso preserves a stable full-page surface during selection. See [ZoomRendering.md](ZoomRendering.md) for invalidation, threading, bounds, source preservation and preview limits.

All 72 selected native regressions and the signed Release build passed. These are functional/rendering checks, not physical Pencil latency, memory or frame-rate measurements. Device installation remains deferred.


### Pinch follow-up

The first physical install exposed a gesture regression despite passing programmatic rendering tests. The corrected build isolates finger navigation to the outer page, defers ink viewport changes until pinch release and restricts fitted-page resets to initial layout/size changes. It passed 74 selected native regressions plus a real XCUI pinch/pan/small-stroke workflow. See [ZoomRendering.md](ZoomRendering.md) and Validation.md for coverage and physical acceptance limits.
