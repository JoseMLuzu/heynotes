# Performance pass — editor, previews and saving

## Findings and implementation

1. **PDF reopen/rerender on every visit.** PDFDocumentService now keeps actor-confined, fingerprinted PDFDocument and image LRU caches. The editor pool retains at most two documents and 24 MiB of image buffers. File path, size, modification date and inode identify the source version. A source is checked before cache lookup, so missing/replaced/corrupt files cannot be hidden by an old cached image.
2. **Gallery work sharing the editor's render queue.** PDF thumbnails use a separate worker actor, one retained PDFDocument and a 4 MiB image pool. Composited page thumbnails use a separate utility-priority actor and a 4 MiB/128-entry cache. Opening/reusing the gallery avoids repeated decoding of unchanged ink. Cancellation is checked before and after rendering and before applying a result to a SwiftUI thumbnail.
3. **Thumbnail resolution growing with document coordinates.** Composite thumbnails are limited to 180 pixels on their longest side, including for a 14400 × 14400 logical-point PDF page. Previously, the 0.15 ink scale produced a 2160 × 2160 raster for that case. The new output has 144× fewer pixels for that particular extreme size; this is a raster-size comparison, not an app-wide RAM measurement. Regular note thumbnails retain comparable display resolution.
4. **Background view backing stores scaling with very large page coordinates.** The paper UIView backing scale is capped to 2400 pixels on its longest side. Logical page/ink coordinates and export geometry remain unchanged. Very large pages can fit the viewport at less than 10% zoom. PencilKit's own rendering scale is not modified.
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
