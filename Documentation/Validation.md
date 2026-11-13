# Phase 1 validation

## Executed in this environment

- Xcode 27.2 (27B52), Swift 6.4.2, iOS Simulator SDK 27.2; deployment target 17.0, Swift 6 language mode.
- **PASS:** generic iOS Simulator Debug build, arm64 and x86_64, code signing disabled.
- **PASS:** five Swift Testing host tests against the production SwiftData models and library view model.
- Tests cover on-disk store reopening, template and inverse relationship persistence, deletion cascade, folder deletion preserving notebooks, independent duplication identifiers and deterministic order, invalid-title rollback, drawing-file safety guards, favorite state and folder moves viewed from a fresh context.
- No external package dependencies were downloaded.

The runner cannot connect to CoreSimulatorService, so simulator launch, screenshots, interaction, iPadOS 17 runtime validation and real Pencil testing were **not performed**. The simulator build succeeding does not establish visual or runtime correctness. CoreData emitted sandbox notification-registration diagnostics during host tests; the tests still completed with all assertions passing.

The first app build could not start Swift's nested macro subprocess sandbox (`sandbox_apply: Operation not permitted`). The successful build used the compiler's supported `-disable-sandbox` subprocess option for this invocation only; the outer workspace sandbox remained active. This is not stored in project settings and is not required in normal Xcode use.

Exact environment-specific commands:

```sh
xcodebuild -project NotesApp.xcodeproj -scheme NotesApp \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/notesapp-derived CODE_SIGNING_ALLOWED=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build

CLANG_MODULE_CACHE_PATH=/private/tmp/notesapp-clang-cache \
  swift test --scratch-path /private/tmp/notesapp-swift-build \
  --cache-path /private/tmp/notesapp-package-cache --disable-sandbox
```

`swift test` is normally enough outside the restricted runner. The package tests metadata on macOS; it does not build or test the SwiftUI iPad interface.

## Manual acceptance checklist

1. Launch an empty installation. Confirm the empty library is intentional, with no generated documents.
2. Create a folder named Biology. Create a notebook with a non-default color and ruled paper in that folder. Check title, date, one-page count, cover and page metadata in its overview.
3. Try blank/whitespace-only titles. Save/Create must be disabled. Rename a notebook using its context menu and search for it with different capitalization.
4. Add a favorite, open Favorites, then remove it. Confirm the list updates.
5. Duplicate a notebook. Rename the copy, delete it after confirmation, and confirm the original remains unchanged. Cancel a deletion and confirm no change occurs.
6. Move a notebook to another folder and to No Folder. Rename and delete a folder. Confirm deletion leaves its notebooks in Library.
7. Close and reopen the app. Confirm notebooks, pages, titles, template, favorites and folder membership persist. Repeat offline.
8. Rotate portrait/landscape and resize the window. Confirm the sidebar collapses and can be restored, grid adapts, and keyboard does not hide form actions.
9. Enable dark mode, large Dynamic Type, VoiceOver and increased contrast. Navigate creation, notebook cards and context menus. Check readable labels and reachable actions without color cues alone.
10. Open Study and a notebook overview. Confirm neither suggests flashcards or handwriting already work. No PDF import/export controls should appear in Phase 1.

## Remaining Phase 1 limitations

- Visual and touch acceptance remains pending because CoreSimulator is inaccessible to this runner.
- A system-provided icon is used until a product icon is designed; App Store packaging is not part of this phase.
- The local store has no backup/recovery UI yet. Opening errors preserve the existing store and display an error instead of resetting it. File-level recovery belongs to Phase 2.
- Binary operations, page editing, export and scheduling tests belong to their implementation phases, not this metadata-only phase.
- UI strings are English. Spanish localization is not implemented; all developer documentation is English as requested.

## Student tools — 2026-11-09

The six authorized student tools are implemented; items 7 (flashcards) and 8 (content/handwriting search) remain deferred. Current verification passes 22 host tests and 47 native simulator tests, including frozen V3 → V4 migration, section/page identity, inserted content undo/reopen, image copying, ruler settings and expanded PDF export. Native editor and practice PDF attachments were visually inspected. The signed device build passes. Physical iPad installation was attempted but blocked by unavailable connectivity (CoreDevice 4016); no app/data removal occurred. See StudentTools.md for exact behavior and the manual acceptance checklist.


## Experimental handwriting style — 2026-11-10

The opt-in phrase conversion prototype passes 24 host tests and 58 native iPadOS 26.5 simulator tests (82 total), including real Vision recognition, stale-result rejection, original ink recovery, Undo/Redo, reopening and font-aware PDF export. The signed device build and installation on the connected iPad Air (5th generation), iPadOS 26.5, succeeded without resetting application data. Native settings and PDF screenshots were visually inspected. Actual cursive recognition and Apple Pencil interaction still require physical-device acceptance. See [HandwritingStyle.md](HandwritingStyle.md) for the user workflow, persistence compatibility, crash recovery tradeoff and limitations.


## Responsiveness — 2026-11-10

The responsiveness pass passed all 71 native tests. After the final empty-page/image-preparation refinements, all 20 targeted loading, autosave, content/export and fluidity tests passed again. Signed Debug and optimized Release device builds succeeded; the Release build was verified to use Swift -O and installed over the existing iPad app with its data retained. See [Fluidity.md](Fluidity.md) for measured text-render samples, exact scope and physical acceptance checks.


## Focus Mode — 2026-11-10

All 74 native tests pass, including Focus Mode menu entry/native exit, nonempty ink and Undo preservation, palette preference restoration, unavailable-page escape, and sidebar gesture policy/restoration in the actual LibraryView hierarchy. Focus screenshots were inspected. The optimized signed Release build and physical iPad installation succeeded without resetting data. See [FocusMode.md](FocusMode.md) for workflow and device acceptance.

## Folder colors and Settings — 2026-11-10

All 79 native simulator tests and 26 host tests pass. New coverage verifies frozen V4 → V5 migration, editable PKDrawing preservation, folder color save/reopen and Trash/restore, preference persistence/fallback, sampled accent contrast and live accent changes without replacing the canvas or changing ink/edit dates. A fixture captured using the actual pre-change V4 models was independently upgraded successfully. Native Settings light/dark and actual library/sidebar screenshots were visually inspected. The signed optimized Release build uses Swift -O and was installed over the existing iPad app successfully (CoreDevice database sequence 2564), after retrying an initial connection reset. No app/data reset or document-file rewrite occurred. See [Personalization.md](Personalization.md) for the implementation, migration and physical-device acceptance checklist.

## Expanded modals — 2026-11-10

All 81 native simulator tests pass. New tests open all 11 app-owned sheet forms through real SwiftUI presentations and verify their initial expanded height without a drag gesture; Settings is also checked in landscape and a narrow window. Native presentation screenshots were visually inspected. The optimized signed Release build succeeds and was installed over the existing iPad app (CoreDevice database sequence 2572), with no data reset. The iPadOS 17 fallback is compile-checked, while runtime verification used iPadOS 26.5. See [ModalPresentation.md](ModalPresentation.md) for the shared sizing policy and physical-device acceptance steps.

## Soft-blue default — 2026-11-11

All 83 native simulator tests pass after adopting the muted-blue default accent and porcelain-white/blue-gray surfaces. The preference-upgrade regression test verifies a one-time legacy-Sage replacement, preservation of appearance and paper settings, and persistence of later/custom color choices. Color-contrast checks use the actual revised canvas and header surfaces. Native editor, library and light/dark Settings attachments were reviewed. The signed Release build and physical iPad installation succeeded, with installation sequence 2644. See [Personalization.md](Personalization.md).

## Parent-folder Back — 2026-11-11

All 84 native simulator tests and 26 host tests pass. The new regression verifies parent-folder navigation through the actual native Back control in LibraryView, with and without existing document tabs, and checks the root disabled/hidden state and preservation of open tabs. Its final appearance-adjusted run also passes. The signed Release update was installed on the connected iPad with installation sequence 2660. See [Workspace.md](Workspace.md) for navigation behavior.

## Library sorting — 2026-11-11

All 85 native simulator tests and 30 host tests pass. New coverage checks natural title ordering, stable equal-title ties, modification-date ordering without metadata changes, PDF classification for mixed-page documents, nested folder activity and the actual native menu preference surviving LibraryView recreation. The final library screenshot was visually reviewed. The signed Release build succeeded and was installed over the existing iPad app with installation sequence 2668. See [Organization.md](Organization.md) for sorting semantics. On iPad, use the arrow-up/arrow-down menu above the grid to switch Name, Recent and Type, then reopen the app to confirm the preference remains selected.

## PDF library previews — 2026-11-11

All 86 native simulator tests pass. The new real NotebookCard regression verifies uncropped landscape PDF edges after a prepended ordinary note page, cached thumbnail reuse and unchanged original PDF bytes. Its final attachment was visually inspected. The test hosts its card in the actual SwiftData model-container environment so delayed layout cannot outlive the fixture store. The signed optimized Release build succeeds and was installed over the existing iPad app with installation sequence 2684. See [Covers.md](Covers.md) for preview scope and loading behavior. Manual iPad acceptance: inspect portrait/landscape PDFs in Library, folders, search and Favorites; reopen a PDF, move it between folders and check favorite badges; verify ordinary notebooks retain their selected covers.

## Startup redraw-loop fix — 2026-11-11

All 88 native tests pass, including two new regressions: repeated palette construction/no-op changes perform no UserDefaults writes, and restoring an active editor alongside library sorting remains responsive through main-actor yields, Library return, native sort activation and reopening. A temporary reproduction using a read-only copy of the iPad metadata/preferences froze before the fix and completed normally afterward. Device reports confirmed watchdog termination and continuous SwiftUI graph updates; temporary invalidation logging isolated the sort preference being invalidated by palette initialization writes. The signed optimized Release build passed and was installed over the existing iPad app with installation sequence 2708. Physical touch acceptance is requested separately; the tests do not claim device FPS or replace that check. See [QuickPalette.md](QuickPalette.md) for the cause and safe persistence guard.

## General fluidity follow-up — 2026-11-11

All 91 native simulator tests pass, including the startup-loop regression. New checks exercise 20 editor parent refreshes with zero additional preference data reads/writes and the same PKCanvasView; an actual 100-point library scroll updating the document-opening frame; and unchanged workspace page memories issuing zero set calls while a changed page persists/restores correctly. The previous editor path recorded 60 data reads for the same 20-refresh workload. Existing toolbar geometry, page/tab navigation, PencilKit Undo/autosave, Focus Mode and PDF import/export tests remain green. The signed optimized Release build succeeded and was installed over the existing iPad app with installation sequence 2716. Physical frame pacing remains a manual acceptance check, not a result inferred from operation counts. See [Fluidity.md](Fluidity.md).

## Apple Pencil double tap — 2026-11-12

All 94 native simulator tests pass. Three new tests check tool history/style preservation, preferred-action routing and ignore/system-owned behavior, and the real installed UIPencilInteraction with live PKCanvasView updates. The native test retains the same canvas, drawing and Undo history, blocks busy/disabled events, toggles the existing tool-options popover and verifies Focus Mode. UIKit animations are disabled only in that test window to avoid coupling correctness to simulator dismissal duration. The Focus Mode panel screenshot was visually inspected. Two earlier simulator launches were rejected as Busy before test execution; restarting the test simulator retained its data and resolved that environment issue. The signed optimized Release build succeeded and was installed over the existing iPad app with installation sequence 2724 after retrying one transient connection reset. Physical gesture recognition still requires a compatible Pencil on the iPad; automated tests invoke the common callback path rather than synthesizing a hardware gesture. See [ApplePencil.md](ApplePencil.md) for mapping, iPadOS 17 fallback and acceptance checks.

## Compact editor menu — 2026-11-12

All 98 native simulator tests pass. Four new tests verify the five-entry first level, paper/PDF relevance, palette recovery, context-sensitive study-tape exports, operations targeting an inactive thumbnail, retained drawing bytes, last-page protection and failed-save blocking. The native top-menu test was then rerun after adding a screenshot capture through the public iPadOS 17.4+ performPrimaryAction API; it passed, and the actual five-row UIKit menu was visually inspected. The signed optimized Release build succeeded and was installed over the existing iPad app with installation sequence 2732. The source changes and documentation remain local, unstaged and uncommitted; no push was performed, as requested. See [EditorMenus.md](EditorMenus.md) for action locations and acceptance checks.

## Continuous full-sheet page turns — 2026-11-12

All 103 native simulator tests pass. The refinement adds five tests covering direct-touch pull geometry and velocity-bounded timing, full-width travel and one queued follow-up, resize cancellation/Reduce Motion, native forward/backward mid-transition rendering with stable viewport/zoom/ink, and programmatic turns from a zoomed sheet. Forward/backward attachments were visually inspected. Existing pending-ink flush, aliased paths, late delegate callbacks, short flicks, 0.5-second creation, Pencil double tap, toolbar/tab behavior and the preceding compact-menu tests remain green. The final optimized signed Release build succeeded and installed over the existing iPad app with installation sequence 2748. Geometry/lifecycle checks do not establish physical hardware FPS or subjective smoothness; dense handwriting/PDF gesture feel remains the iPad acceptance check. Changes remain local, unstaged and uncommitted, with no push. See [PageGestures.md](PageGestures.md).

## Prepared neighboring pages and shorter gesture waiting — 2026-11-12

All 109 native simulator tests pass. Six new preparation tests check actual decoded-value reuse, changed/missing/corrupt ink, replaced/corrupt images and object metadata, bounded retention/clearing, shared-consumer cancellation and memory-generation behavior, and navigating back to the newest saved strokes after neighbor preparation. Existing alias/same-page reload, failed-save, PDF, Pencil, menu and motion tests remain green. The rapid-flick motion test also verifies the same animator is retained with a tail of at most 60 ms. A 20-load simulator sample measured 7.787 ms unprepared versus 5.173 ms prepared, with one prepared load and 20 reuse hits; these timings do not establish device FPS or guarantee zero perceived latency. The signed optimized Release build succeeded and installed over the existing iPad app with installation sequence 2756. Source changes remain local, unstaged and uncommitted; no push was performed. See [PagePreparation.md](PagePreparation.md) for freshness checks, cancellation, memory budgets and hardware acceptance.

## Interactive paging and prepared native canvases — 2026-11-12

All 114 native simulator tests pass. Five new tests cover release-only commit with short flicks/reversal, actual two-sheet interactive geometry in both directions, cancelling without replacing ink, viewport rotation, stale decoded-identity rejection, memory release, and SwiftUI activation of the exact prepared PKCanvasView after the outgoing drawing reaches disk. Returning to the source preserves its latest drawing. Existing failed-save, aliased-path, PDF export, Pencil, menus, autosave and workspace tests remain green. Interactive forward/reverse screenshots were exported and visually inspected. The signed optimized Release build passed and installed over the existing iPad app with installation sequence 2764, preserving its bundle ID and data store.

Prepared hosts are bounded to two neighbors and allocated on the main actor between interactions. Local Instruments signposts isolate foreground loading, save, native preparation and accepted-release-to-animation-completion; they contain no note content. The suite establishes object reuse, geometry and persistence correctness, not physical Pencil latency, actual display FPS or zero delay for cold/evicted pages and required saves. Manual acceptance: short and slow flicks, reversing before lifting, dense handwritten/PDF pages, repeated turns, rotation, background/save failure, Reduce Motion, and the unchanged 0.5-second last-page creation hold. Source changes remain local, unstaged and uncommitted; no push was performed. Implementation and measurement details: [PagePreparation.md](PagePreparation.md).

## Screenshot-driven navigation and pages panel — 2026-11-12

All 115 native simulator tests pass. The new floating-index test covers dragging its native handle, changing position, narrowing the viewport, closing, hit testing outside the panel, and retaining the same canvas, page objects and undo history. Existing library folder-back/sort, toolbar, gesture, save and PDF suites remain green. Library and panel screenshots were exported and visually inspected. The optimized signed Release build passed and installed over the existing iPad app with installation sequence 2788; the bundle ID and document store were preserved. Physical layout acceptance remains the user's check on their actual iPad. No commit, staging or push was performed. See [EditorNavigationLayout.md](EditorNavigationLayout.md) for action locations, API availability and manual checks.

## Colored-band correction and thumbnail ordering — 2026-11-12

The user's clarification replaces the movable panel with a fixed counter-anchored popover and enables dragging the page thumbnails themselves. The extra 16-point white content inset is removed; instead the colored navigation background extends 16 points below its controls/tabs. The same circular back and single-sidebar controls remain.

All 117 native tests pass. The replaced panel suite now checks native transfer encoding/decoding, order persistence through a fresh ModelContext, both move directions, section changes, unchanged permanent IDs/bookmark/paths, active-canvas and undo retention, pending ink saved to the correct page, and invalid/busy/missing/self-drop rejection. The real popover test verifies drag/drop interaction registration and fixed geometry while ordering changes. After passing the editor's DrawingStorage into PageThumbnail, these three tests were rerun and passed; final thumbnails and the extended colored band were visually inspected. This does not synthesize a physical iPad long-press drag. The final signed optimized Release build passed and installed over the existing iPad app with installation sequence 2796. No commit, staging or push was performed. See [EditorNavigationLayout.md](EditorNavigationLayout.md) for the final behavior and manual acceptance.

## Recorded page-turn pauses — 2026-11-12

Reviewed the user's 17.86-second recording using AVFoundation frame extraction, an overview contact sheet and 50 ms samples. It shows interrupted-looking/repeated page movement, including nearly empty pages; it does not by itself identify CPU stalls, gesture release times or physical display FPS. The code had a definite wait at release: a prepared sheet stayed at its pull position until the safe open published its destination. Three new regressions failed before the change, reproducing the absent pre-publication animator, absent rollback lifecycle and an offscreen prepared canvas under Reduce Motion.

The fix starts prepared visual movement at release, adopts the same animator after save/source validation, and keeps an early-settled preview read-only. Failed saves restore both sheets and pending ink; changed validated content replaces the speculative view from the visible position. Rejected callbacks clear both-sheet pull state. Completed turns can retain a clean outgoing native canvas for a validated return. Native unchanged-drawing callbacks no longer create false dirty revisions, and warm-up avoids edge-return/deceleration/pending-open work.

All 124 native tests pass. Seven added cases cover pre-publication movement and same-animator adoption, completed-preview rollback, prepared Reduce Motion visibility, repeated unchanged callbacks versus actual edited ink, eight rapid forward/backward flicks through the real page callback (including reuse of the original returning PKCanvasView), stale/rejected preview cleanup, and a real filesystem save failure retaining the original active page/canvas/drawing. Existing save, cold/aliased loads, recovery, PDF, reorder, toolbar and geometry tests remain green. Signed optimized Release built and installed over the existing iPad app with installation sequence 2804. The physical Time Profiler attempt timed out waiting for the connected device; no device timing/FPS improvement is claimed. Manual acceptance should repeat the recording's quick back-and-forth sequence on the iPad, including dense ink and PDF pages. Cold uncached pages and mandatory save/validation can still delay editing. Source changes remain local, unstaged and uncommitted; no push was performed. See [PagePreparation.md](PagePreparation.md).

## Local scoped commit packaging — 2026-11-12

At the user's explicit request, the accumulated implementation, tests and documentation were packaged into 12 local scoped commits. Changes are grouped by targeted page actions, compact menus, navigation, decoded-content caching, adjacent-page preparation, container extraction, continuous native transitions, three focused test groups, thumbnail reordering and documentation. The source/test contents match the previously validated 124-test implementation; the only source formatting cleanup removes an extra trailing blank line from the extracted container.

Archived committed snapshots for the menu, preloading, transition and final reordering milestones each passed native simulator build-for-testing independently of later working-tree changes. Documentation now reflects the authorized local commits; earlier entries retain their historical no-commit status at the time of validation. No push was performed.

## Selective PDF import — 2026-11-12

All 131 native simulator tests pass. Seven new tests cover range/index validation, whole-document and single-page selection behavior, failure recovery, cancel cleanup without library metadata, duplicate-confirmation blocking, surviving loss of the picker source after staging, invalid selections, source-index mapping, rotated geometry, source-byte preservation, editable ink, and exports containing only selected pages. A real expanded sheet is captured in portrait and landscape; activating its native segmented control exposes the range field and empty-selection state. Those screenshots were exported and visually inspected. Existing PDF import/export/protection/corruption, library, page-ordering, PencilKit and save tests remain green.

The signed optimized Release build passed and installed over the existing iPad app with installation sequence 2812 after retrying a transient connection reset. The same bundle ID and document store were retained. Physical Files-provider picker and selection acceptance remains the user's iPad check. No schema migration, commit, staging or push was performed for this feature. See [SelectivePDFImport.md](SelectivePDFImport.md) for the full workflow, temporary-copy lifetime and the preserved full-source storage tradeoff.

## Automatic sidebar closing — 2026-11-12

Document activation now selects the detail-only NavigationSplitView layout and its compact detail column, including an initially restored editor. The existing sidebar button can reopen it without a persistent auto-hide loop; folder navigation is unchanged. The six existing LibraryNavigationTests and FocusModeTests passed, and the signed optimized Release build succeeded. The app installed over the existing iPad app with installation sequence 2820, preserving its bundle ID and document store. No new tests were added for this small presentation change. No commit, staging or push was performed; the preceding selective-PDF-import changes remain local as well.
