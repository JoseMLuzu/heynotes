# Responsiveness pass — 2026-11-10

## Changes and scope

This pass reduces unnecessary work before adjusting motion. The app keeps one active editor, the existing safe autosave pipeline, the current page-turn gesture/animation and all document recovery behavior. No SwiftData schema or file-format migration is introduced.

### Tool updates

`ToolPreferences` previously observed one aggregate `Saved` value. Changing a stroke width invalidated observers that only needed the selected tool or ruler. The stored aggregate is now excluded from automatic observation; computed UI properties register access/mutation individually using Observation's public facilities. Derived ink/favorite properties also observe selection, so changing tools still refreshes the correct style. Identical assignments return early instead of rewriting preferences and notifying UI subscribers. Existing Codable keys, defaults and synchronous local persistence are retained.

`EditorCanvasContent` isolates high-frequency ink/tool reads from the parent editor. Color and width changes update the canvas and tools without forcing the parent to rebuild navigation, modal declarations and the native Page Options menu.

### Drawing and text

The object overlay no longer requests a display pass when its selected ID or revealed tapes are assigned the same values. Entering/leaving object selection and actual zoom changes explicitly redraw its outline, preserving the behavior previously supplied by unconditional redraws. Image identity changes explicitly invalidate the content view.

Each canvas content view owns a text-layout cache with a 64-entry NSCache count limit. Its signature includes text, public font name, font size, rectangle dimensions and color/opacity; position and recovery ink are excluded. Moving text therefore reuses typesetting; resizing, editing or recoloring rebuilds it. The cache belongs to one view/drawing thread and is never shared with PDF or thumbnail workers, in accordance with Core Text's layout-object threading requirements. Cache eviction may rebuild layouts and never removes document data. The count limit is not a cap on total application memory.

The renderer is shared with PDF/thumbnail rendering; those callers create their own uncached layouts. Pixel-equality tests compare cached and uncached canvas rendering.

### Opening content

Inserted-content JSON can contain significant archived source ink. Opening/recovering a page now decodes that JSON in a cancellable detached task instead of on MainActor. Image loading also uses a detached task and prepares common images for display before publishing them. Eager preparation has a per-load 24 MiB estimated RGBA pixel budget; remaining images retain lazy decoding. That estimate is not a total-memory limit. Empty metadata/image collections use fast paths without launching needless workers. Missing/corrupt data still propagates errors, and cancelled tasks cannot publish results.

Original drawing/PDF loading, same-path save ordering, atomic checkpoints and flush-before-navigation are unchanged. There is no speculative stale document cache or skipped save boundary.

### Library and motion

The library computes its visible folders/documents once per render rather than filtering repeatedly within one layout. The scoped nearest-scroll-view touch policy is now a Core component reused by the library and tool overflow; it does not modify global UIScrollView appearance or the page canvas.

Sidebar hit testing uses observable operation state rather than capturing UIKit's non-observable Pencil gesture state in a rendered flag. Actual document navigation continues to check the live gesture in the workspace.

Library buttons give immediate pressed feedback and settle on release in 90 ms. The existing compositor-only notebook-opening transition is shortened from 280 to 220 ms; its temporary interaction gate is 240 ms instead of 300 ms. Reduce Motion still bypasses it. The page-turn animation remains unchanged to preserve the existing no-flicker behavior and 0.5-second page-creation hold.

## Measurement

A deterministic Debug simulator workload draws 12 text objects over 20 refreshes using the production renderer, after warming system font resources. The same workload runs uncached and with a fresh per-view cache.

| Workload | Uncached | Cached |
| --- | ---: | ---: |
| Core Text layouts created | 240 | 12 |
| 20 refreshes, sample 1 | 8.035 ms | 3.722 ms |
| 20 refreshes, sample 2 | 7.651 ms | 3.643 ms |

These are local simulator samples of one small workload. They do not establish hardware FPS, Pencil latency, or an app-wide speedup. Tests assert layout reuse and identical pixels, not a timing threshold. Runtime artifacts are stored by XCTest, with a `FLUIDITY` timing line in the test logs.

## Verification

All 71 native tests passed after the main changes. Following empty-page fast-path and bounded image-preparation refinements, all 20 targeted fluidity, page loading, autosave and inserted-content/PDF tests passed again. The signed Debug device build also succeeds.

Five new tests cover granular Observation dependencies, unchanged-value notifications, overlay invalidation, text-layout reuse and relevant-edit invalidation, cached/uncached pixel identity, the repeated-render workload, cancelled/corrupt content decoding, and actual image pixel dimensions/corruption handling.

## Physical acceptance

Use the optimized device build to compare rapid tool/color/width changes, tapping the top ellipsis just after writing, library scrolling/opening, page/tab switches, text dragging, portrait/landscape docking and opening an image-rich page. Check Undo/Redo, background/reopen and PDF export. Dense notes and long PDFs should also be reviewed in Instruments for main-thread stalls, animation hitches and peak allocations. Physical responsiveness remains an acceptance task; successful tests/install do not substitute for that measurement.

## References

- [ObservationRegistrar](https://developer.apple.com/documentation/observation/observationregistrar)
- [Core Text threading requirements](https://developer.apple.com/documentation/coretext)

## Optimized device build

The signed Release build succeeds. The app compile command was verified to use Swift `-O`; unit-test target settings remain separate. The Release build uses the existing app bundle identifier and local store. Future runs from Xcode's default Debug scheme will use Debug optimization settings again; the source-level changes in this pass remain present in both configurations.

The optimized Release app was installed successfully on the paired iPad after retrying a transient CoreDevice connection reset. The existing app/data container was retained; no uninstall, migration or data reset was performed.

## General responsiveness follow-up — 2026-11-11

This pass targets repeated work during library scrolling, editor updates and navigation. It follows the confirmed startup-loop correction in [QuickPalette.md](QuickPalette.md).

### Editor control lifetime

EditorView previously constructed temporary ToolPreferences and QuickPalettePreferences objects whenever its value was rebuilt, even though SwiftUI retained the original State instances. A lazy StateObject now owns EditorControlPreferences once per editor identity. Its two contained Observation models keep granular tool/palette observation. Existing palette injection, toolbar placement, tool selection, canvas identity and document-specific presentation reset behavior are preserved. The owner is local to the editor, with no global editor cache.

### Library scrolling and opening

Notebook cover geometry previously flowed into LibraryView's coverFrames State dictionary during scrolling. That invalidated the root library, including filtering/sorting, sidebar and menu construction. LibraryNotebookTile now captures its own latest cover frame in a non-observable reference. Scrolling updates this opening coordinate without changing root library state. Tapping supplies the current frame to the existing zoom transition; a native scroll test verifies that moving the library by 100 points moves the opening origin by 100 points while preserving cover dimensions.

### Workspace persistence and page lookup

DocumentWorkspace compares complete semantic navigation snapshots before encoding/writing preferences. Repeated rememberCurrentPage calls with unchanged tab order, active notebook, recent history and page IDs skip the write. Actual navigation and remembered-page changes still persist, and restore still prunes unavailable documents. Ink flushes and failure blocking remain independent of this preference optimization. Activation finds the remembered page directly or selects the stable minimum page index/UUID in linear time instead of sorting every page.

### Measured work and limits

| Workload | Before | After |
| --- | ---: | ---: |
| Preference data reads during 20 parent editor refreshes | 60 | 0 |
| Additional preference writes during those refreshes | 0 | 0 |
| UserDefaults.set calls during 50 unchanged page-memory updates | 50 (previous unconditional path) | 0 |

The editor workload hosts the production SwiftUI editor and verifies the same PKCanvasView survives. The workspace workload counts actual set calls and verifies that a real page change writes once, restores the correct page and permits later no-op updates. These are operation counts, not filesystem-write counts or frame-rate measurements. The refresh harness also logs elapsed wall time; task scheduling and SwiftUI update coalescing vary, so that value is not used as a speedup metric. Physical frame pacing and Apple Pencil latency remain device acceptance measurements.

Run the FluidityTests, DocumentOpeningTests and DocumentWorkspaceTests classes to reproduce these checks. For physical acceptance, compare library scrolling/opening, rapid tab/page switches, tool/color/width changes and menu opening. Check Undo/Redo, Focus Mode, toolbar docking, background/reopen and PDF preview/export with a dense handwritten notebook.
