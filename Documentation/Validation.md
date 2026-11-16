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


## Published PDF/sidebar work and PlainJot roadmap — 2026-11-13

At the user's request, the selective-PDF import and automatic sidebar-closing changes were packaged into three scoped commits and pushed to origin/main: c17d92a, e8d0e5c and 7d72c6b. Local main and origin/main were verified at 7d72c6b. Their preceding validation is recorded above.

PlainJot project “Notes — iPad” now contains “05 — Current Status & Prioritized Next Steps — 2026-11-13”, written in English. Its saved preview was verified. It records published work, remaining library/reliability tasks, deferred capabilities, Phase 4 Study requirements and release preparation. Phase 4 implementation has not started.

## Compact short-content sheets — 2026-11-13

New Folder, New Subfolder and Rename use a compact initial title form. Folder Color and PDF Note Margin also open compactly. Longer forms retain the expanded presentation. Scaled preferred heights, native scrolling and keyboard avoidance support normal text/window changes; accessibility text sizes use the expanded policy. iPadOS 18 fitted sizing is availability-guarded with an iPadOS 17 detent fallback. No metadata or drawing-storage changes are involved.

The two updated native ModalPresentationTests pass, covering 12 actual forms plus landscape, narrow-window, title-input focus/visibility with the keyboard, and accessibility text. New Folder, Folder Color and PDF Margin screenshots were exported and visually inspected. The earlier full 131-test suite was not rerun for this presentation-only change. The signed optimized Release build passed and installed over the existing iPad app (installation sequence 2828), preserving its bundle ID and store. Physical-device interaction remains a manual acceptance check; iPadOS 17 fallback validation is compile-only.

The same PlainJot note was updated with these results, installation status and remaining physical acceptance, then verified as “Todo guardado”. These new modal code/test/documentation changes remain local and uncommitted; the three earlier PDF/sidebar commits are already pushed. See [ModalPresentation.md](ModalPresentation.md) for sizing policy and manual acceptance.

## Phase 4 — Study and flashcards — 2026-11-13

Study now provides real deck/card creation and editing, optional notebook association, permanent source-page links, recoverable deck/card Trash, question/answer turns, ratings, due review queues and saved progress/history. The editor's Page submenu includes manual Create Flashcard with the current source preselected after an ink flush. Source opening targets its permanent page ID and clears a pushed Study route before showing the editor. Existing notebook/page/drawing fields remain unchanged.

The full native suite passed 135 tests after the Study implementation, including four new integration tests and expanded real-sheet coverage for 15 forms. After adding the explicit Study navigation route, 14 focused native tests passed (five Study, three library navigation, two modal presentation and four editor menu tests). Following the final local-calendar Due today refinement, all five Study integration tests passed again. The final host suite passes 37 tests, including eight Study tests: exact rating intervals/progression/lapses/caps and invalid values, disk reopen with immutable review history, Trash/restore, failed review/create/edit rollback, skipped-card semantics, independent pending-editor metadata, stable source links/reordering/deleted and trashed sources, local DST boundaries, and the actual previously shipped V5 top-level model layout.

Native migration tests preserve notebook/section/page UUIDs, folder color, bookmarks, PDF metadata and external file bytes across V5 → V6. Prior unversioned/V2/V3/V4 migration tests remain green. Native integration verifies real PKDrawing data flushed before opening a source, same-notebook explicit page navigation, missing/trashed-source rejection and return from a pushed deck to the editor and Study. Final dashboard, deck and accessibility screenshots were exported and visually inspected; earlier question/answer, dark landscape and completion captures were also inspected. The screenshots establish layout, not synthesized user touch or physical device performance. Reduce Motion uses the system environment; physical gesture and VoiceOver acceptance remain manual.

The signed optimized Release build passed and installed over the existing iPad app (installation sequence 2860), retaining com.local.notesapp and the existing store. Runtime automated validation uses iPadOS 26.5; iPadOS 17 availability is compile-checked. No commit or push was performed for Phase 4; the preceding compact-modal changes remain local too. See [Study.md](Study.md) for architecture, exact scheduler rules, files, usage and acceptance steps. No Phase 5 work was started.

## Requested sample deck — 2026-11-13

The user explicitly requested a test deck. The focused sample-creation regression passed: eight immediately due cards, repeated invocation without duplication or review reset, and preserved Trash state. The signed Release build passed and installed over the existing iPad app with sequence 2868 after retrying one transient transport reset. Launching with the explicit development argument created the real “Mazo de prueba · Repaso general” deck. Its non-content receipt was retrieved from the device and verified: deck UUID 7791E314-7164-41E0-88E3-E08AD30EF5FA, eight cards, not trashed. No notebook data was copied for verification. Ordinary launches do not seed sample content. No commit or push was performed.

## Two-document workspace — 2026-11-13

The editor now supports two different notebooks/PDFs through a shared tab strip and independent editable panes. The split button opens a document picker; tab context menus offer Open Beside. Pane titles identify focus; the divider resizes the arrangement, Swap Panes retains view identity, and Keep Focused Document Only preserves the retained editor and the other file as a tab. Narrow windows stack the editors. The workspace preference adds optional pane IDs/order/fraction without a SwiftData schema or document-file migration.

All 141 native simulator tests passed. After correcting competing Focus Mode sidebar policy owners, nine focused tests passed, including the sixth new split regression. Coverage includes distinct real PKCanvasViews/ink/tools/Undo, focused Pencil double-tap routing, passive initial-touch focus, identity across resize/swap/secondary-pane retention, legacy JSON and split restoration, permanent page IDs, alias/missing/trashed-source rejection, failures blocking replacement/closing/Library/subtree removal without losing pending ink, background saves and independent note/PDF navigation/export with original PDF bytes/dimensions intact. Existing tab-toolbar identity/scroll-offset, save, page-turn, Study, import/export and recovery tests remain green. Native landscape, narrow stacked and Focus Mode attachments were visually inspected.

The signed optimized Release build passed and installed over the existing iPad app (installation sequence 2876), preserving com.local.notesapp and its data store. Runtime checks used iPadOS 26.5; iPadOS 17 availability is compile-checked. Hardware Pencil gesture/latency, VoiceOver and display frame pacing remain physical acceptance checks. No host tests were rerun for this iPad editor change. No commit or push was performed. See [SplitWorkspace.md](SplitWorkspace.md) for architecture, state compatibility and acceptance steps.

## Flashcard review refinement — 2026-11-13

Review uses a stable card viewport, fixed turn-control bounds and a reserved rating region. Tapping the card or Reveal Answer turns it; View Question occupies the same control bounds. Ratings fade into their reserved area and use balanced four/two/one arrangements, symbols, light color cues and actual interval previews. Rounded system typography, centered scrollable content, semantic surfaces and quiet borders replace the previous top-heavy card. Reduce Motion disables turn/fade animations. Hidden rating controls are disabled and accessibility-hidden; visible-card identity guards stale rating callbacks. Stored cards, history, scheduler and migration code are unchanged.

Six focused native tests passed: the new measured-layout regression and five existing Study integration tests. Real SwiftUI bounds for the card, turn button and Skip are unchanged within 0.5 points before/after reveal, after turning back, and after advancing to a long-content card across 820×1180, 1180×820 and 540×820 windows. The regression drives the same StudyReviewSession actions used by the controls; it does not synthesize a physical tap. Native question/answer, narrow balanced-rating, dark landscape and accessibility-text screenshots were exported and visually inspected. Full app/host suites were not rerun for this presentation-only change.

The signed optimized Release build passed and installed over the existing iPad app (installation sequence 2884), retaining its bundle ID, notebooks, study deck and saved review data. Runtime automated checks used iPadOS 26.5; API availability compiles against iPadOS 17. Physical tap/scroll/VoiceOver and Reduce Motion acceptance remain iPad checks. Code and English documentation remain local and uncommitted; no push was performed. See [Study.md](Study.md) for the final presentation behavior and unchanged scheduler policy.

## Practice All and repeatable decks — 2026-11-13

Every nonempty deck now offers Practice All independently of scheduled due dates, alongside Review Due Cards when appropriate. Free practice includes future cards, reveals/advances with Next Card and offers Practice Again on completion. It does not record difficulty ratings or change scheduled progress. Repeat rounds reset local position/face/count and exclude unavailable members of the original snapshot. Stored models and migration remain unchanged.

All 39 host tests passed. The new domain regression starts with a fully scheduled deck, includes future cards, excludes other-deck/trashed cards, rejects scheduled grading in practice, completes/repeats rounds with storage writes forbidden, verifies unchanged review dates/intervals/repetitions/lapses/updatedAt/history, and handles subsequent card/deck Trash. Seven focused native tests passed: six Study integration cases and the measured-layout case now covering both scheduled and practice modes at three window sizes. The new native case captures a deck with zero due cards, practice question/answer, and Practice Again, verifying history and dates remain unchanged. These captures were exported and visually inspected. Full native tests were not rerun; scheduled save/failure coverage remains in the passing host suite.

The signed optimized Release build passed and installed over the existing iPad app (installation sequence 2892), retaining the existing library and study data. Physical tapping and repetition flow remain user acceptance checks. Documentation is updated in English. No commit or push was performed. See [Study.md](Study.md) for practice semantics and unchanged scheduling rules.

## Active-tab close without a Library flash — 2026-11-13

Closing the last visible editor previously cleared its session before awaiting the next open tab's drawing load. LibraryView rendered Library during that suspension. The close operation now saves the outgoing editor, prepares the successor while retaining the outgoing canvas, and replaces the session directly in its existing presentation slot. Closing the final tab still intentionally returns to Library. Save failures retain the current tab and pending ink; no schema or stored-document changes are involved.

A new native regression reproduced the failure before the fix in both primary and retained-secondary slots. It deliberately holds an isolated drawing-storage executor while the actual LibraryView renders, then verifies the outgoing session, canvas and native toolbar identity remain present and the Library sort control never appears. After releasing the read, it checks the ready successor, stable slot/control identity, unchanged notebook count and intentional Library return after the final close. All 13 focused tab, split-workspace and transition tests passed after the fix. Loading/ready primary-slot screenshots were exported and visually inspected. The signed optimized Release build passed and installed over the existing iPad app with installation sequence 2900, preserving its bundle ID and data. Physical transition smoothness remains an iPad acceptance check. No commit or push was performed.

## Portrait sidebar layout — 2026-11-13

Portrait windows and widths below 1,000 points now enter detail-only navigation. Reopening the sidebar requests a narrower 236-point ideal (220–250-point range), includes an explicit close control and dismisses on destination changes. Wide landscape keeps the previous column widths and restores its remembered visibility. Opening an editor also updates that remembered visibility to detail only. A GeometryReader measures the app window; no alternate navigation hierarchy, metadata migration or document writes are introduced.

All eight focused native navigation, Focus Mode and tab-close tests passed. The new regression measures actual detail width at 820×1180, 1032×1376 and 620×820, checks native sidebar width and selection dismissal in regular-width portrait, restores wide layout and retains the active PKCanvasView through resizing. Compact navigation is checked through visible content width because its native displayMode does not describe the collapsed stack. Exported portrait open/closed and narrow-window captures were visually inspected after native transitions settled. The signed optimized Release build passed and installed over the existing iPad app with sequence 2908, preserving its bundle ID and data. Physical rotation, sidebar taps and Pencil interaction remain user acceptance checks. No commit or push was performed. See [EditorNavigationLayout.md](EditorNavigationLayout.md) for the sizing and restoration policy.

## Scoped local commit batch — 2026-11-13

At the user's request, the pending compact-modal, Study, sample-deck, dual-editor, tab-close and portrait-sidebar work is packaged into 17 scoped local commits. Persistent models, scheduling/data services, their tests, forms, review components, deck navigation, source integration, workspace state, native touch observation and visual fixes are separated. Xcode source registration follows each source addition rather than referring to later files. Earlier no-commit statements above describe the validation state at those milestones.

Archived proposed snapshots for the integrated Study and two-editor milestones each passed simulator build-for-testing independently of later working-tree changes. The isolated Study domain snapshot passed all 38 host tests before adding the separately committed sample deck. The final sample-inclusive host suite and targeted native/runtime/device validation are recorded above. These packaging checks do not add physical Pencil or rotation acceptance. No push is included in this batch.

## Library sidebar/back alignment — 2026-11-14

The supplied iPad captures showed different leading margins for the native sidebar button and the custom back-button row. A new native regression reproduced their horizontal-center mismatch before the fix: 2 points with the sidebar closed and 8 points with it open in landscape. Library now measures the native control center and detail horizontal bounds to supply the lower row's leading inset. The measurements are independent of the adjusted padding; the native toolbar, 44-point back hit area and editor tab-row defaults remain intact. No models, navigation actions or drawing persistence changed.

All nine focused native LibraryNavigation, FocusMode and TabCloseTransition tests passed after the change. The new regression measures actual rendered controls within 0.5 points in landscape and portrait with the sidebar open and closed. Landscape open/closed and portrait open screenshots were exported and visually inspected. The signed optimized Release build passed. Device installation was attempted but failed with CoreDevice error 3002 / NSPOSIXErrorDomain 28: the iPad has no space to create installation staging data. The corrected build was not installed; free device storage before retrying. No user data was removed, and no commit or push was performed. See [EditorNavigationLayout.md](EditorNavigationLayout.md) for the measured alignment and iPadOS 17 availability policy.

The subsequent user-requested installation retry succeeded with sequence 2992. The same tested Release build then launched successfully through devicectl on the physical iPad. The previous storage-related installation block is resolved; physical alignment acceptance remains the user's check.


## Local library backups — 2026-11-14

The first CloudKit preparation milestone adds actual complete-library backup and additive restore in Settings. The V6 SwiftData schema, existing store and local-only configuration are unchanged. No CloudKit entitlement, upload or sync UI is enabled.

- **PASS:** 45 host tests (13 suites), including six new backup tests. Coverage includes disk-store reopening; nested folders, favorites and Trash; editable drawing bytes and checkpoints; 2.1 MB streamed images; immutable PDF bytes; original-ink object payloads; deterministic drawing recovery; duplicate-ID remapping; source-note links and review history.
- **PASS:** 18 targeted native simulator tests on iPad Pro 13-inch (M5), iPadOS 26.5: four new LibraryBackupIntegrationTests plus SplitWorkspaceTests, StudyIntegrationTests and ModalPresentationTests. Both live canvases flush uncaptured native ink before export, blocked saves retain pending ink, a real PDF round-trips and exports with its dimensions, Study references remain valid, and dismissed previews/native picker completion cleanup is verified.
- **PASS:** malformed/truncated archives, checksum mismatch, future format versions, missing assets, unsafe/duplicate paths, symlinks, cycles, staged tampering, cancellation and injected metadata-save failure leave existing data intact.
- **PASS:** simulator Debug build (arm64/x86_64), signed physical-iPad Release build, and `git diff --check`. No external dependencies were added.
- **PASS:** signed Release installed and launched on the connected iPad Air (5th generation), retaining existing application data (installation sequence 3028).
- Backup settings were visually inspected from a native portrait rendering. Restore previews were rendered in dark landscape and large-text narrow layouts and retained as test attachments.

Commands and results: `/private/tmp/heynotes-backup-host-tests.log`, `/private/tmp/heynotes-backup-native-tests.log`, `/private/tmp/heynotes-backups-release.log`; native result bundle `/private/tmp/heynotes-backups-sim/Logs/Test/Test-NotesApp-2026.11.14_16-37-23--0500.xcresult`.

Physical Files-provider export/import, large production libraries and minimum-iPadOS-17 runtime acceptance remain manual checks. No real user library was used as a test fixture or uploaded. Backups are uncompressed and unencrypted; metadata and file-count limits and the filesystem/SQLite interruption window are documented in [LibraryBackups.md](LibraryBackups.md). See [CloudKitPreparation.md](CloudKitPreparation.md) for the following milestones.


## Full release-readiness audit — 2026-11-14

The owner confirmed offline v1.0, with iCloud after launch. This task audited and documented the product; it did not implement release tasks, commit/push, upload, or publish.

- **PASS:** all 45 host tests in 13 suites, current working tree. Log: `/private/tmp/heynotes-audit-host-tests.log`.
- **PASS:** all 151 native tests on iPad Pro 13-inch (M5), iPadOS 26.5, 99.771 seconds; this supersedes the prior 18-test focused backup run as the current full regression baseline. Log: `/private/tmp/heynotes-audit-native-tests.log`; result: `/private/tmp/heynotes-backups-sim/Logs/Test/Test-NotesApp-2026.11.14_20-27-09--0500.xcresult`.
- Inspected the existing signed Release artifact: display name Notes, bundle com.local.notesapp, version 0.1.0/build 1, minimum 17.0, SDK 27.2, iPad only. AppIcon is present; no bundled `.xcprivacy` manifest was found. Settings lacks privacy/support links. No App Store archive validation or account-state verification was performed.
- Full-suite logs contain SQLite open-file-unlink warnings from temporary test-store teardown; test cleanup should release contexts/stores before removing those fixtures. These isolated warnings do not establish corruption of production user data.
- Physical Pencil/Files-provider/large-library/recovery/accessibility acceptance and minimum-OS runtime checks remain open. Development install/launch from the previous milestone is not completion of those gates.
- Updated all six existing PlainJot project documents, added an iCloud-after-launch roadmap and validation plan, and created six proposed Inbox tickets. All references and map parent chains validated; original notes preserved under the vault’s `.history` directory.

See [ReleaseReadiness.md](ReleaseReadiness.md) for inventory, blockers, estimate assumptions, App Store references and release gates. The 4–6-week planning range is an estimate with conditional assumptions, not a promised ship date or Apple review duration.


## Toolbar-to-palette dragging — 2026-11-14

Direct tool icons can be dragged into Quick Palette with their own captured settings; favorites can be reordered in place. The existing v2 preferences and document schema remain unchanged. Same-profile reorder retains IDs/settings; insert/cross-profile/cross-pane copy creates a new favorite; full/invalid/stale/busy drops preserve existing favorites. Palette-only hover/reorder feedback preserves the live canvas.

- **PASS:** all 157 native tests, including six new PaletteToolDragTests; `/private/tmp/heynotes-palette-drag-full-tests.log`, result `/private/tmp/heynotes-backups-sim/Logs/Test/Test-NotesApp-2026.11.14_21-13-35--0500.xcresult`. The earlier host baseline remains 45 passing tests; this change lives in the iPad editor target.
- **PASS:** actual NSItemProvider encode/decode/async receive, inactive-tool snapshot without selection/defaults writes, persisted insertion/order, six-favorite limit, independent IDs/source profiles, changed destination rejection, blocked/malformed/multiple items, native drag/drop interaction presence at all four toolbar positions, and unchanged PKCanvasView identity/page timestamps.
- **PASS:** signed iPad Release build; screenshot after adding a sixth favorite with the side toolbar visually inspected; Info.plist and `git diff --check` pass.
- The first focused regression run passed all six new cases but failed the FocusMode sidebar-gesture assertion once. The subsequent full 157-test run passed on identical focus code. Track this as a timing-sensitive validation finding; no production focus workaround was added in the drag feature.
- Physical long-press/finger gesture feel and fast-tap acceptance remain manual checks. See [QuickPalette.md](QuickPalette.md) for the exact workflow, local data boundary and device checklist. No commit or push was performed.

## Expanded student tools — November 14, 2026

- Host: **50 tests passed** (`/private/tmp/heynotes-expanded-host-tests.log`). Real frozen V6 store migration preserves IDs, drawing bytes, source links and review schedule/history. Captured-card assets survive backup/remapped restore; record format 1 remains readable.
- Simulator: **172 tests passed, zero failures**, including 15 new expanded-tool tests (`/private/tmp/heynotes-expanded-verified-tests.log`; result bundle `Test-NotesApp-2026.11.14_22-09-59--0500.xcresult`). Existing native gestures, editor persistence/export, Study and workspace regressions pass.
- New coverage includes whole-marker-only erasing with masks/transforms, source-ink recovery and combined Undo, stale-page rejection, folded note persistence, selectable PDF line geometry checked against actual cropped/rotated raster output, independent PNG crops/card images, live secondary-canvas flush, correct clear/Undo behavior and failure retention.
- Inspected native attachments for both window orientations, region-card creation/review and PDF highlighting. Final fit/centering refinements receive a focused tool-suite rerun. Physical Pencil latency/hold/region gestures still need hands-on acceptance.
- Xcode 27.2, Swift 6.4.2, SDK 27.2; deployment remains iPadOS 17. Signed Release build succeeds. No commit or push is part of this work.

Final layout check: all **15 expanded-tool native tests passed again** (`/private/tmp/heynotes-expanded-final-layout.log`, result `Test-NotesApp-2026.11.14_22-12-20--0500.xcresult`); inspected the centered crop form and fitted writing window. Final signed Release build: `/private/tmp/heynotes-expanded-release-ready.log`, **BUILD SUCCEEDED**. Physical installation was attempted but CoreDevice rejected developer-disk mounting because the iPad was locked (12040 → 10003). The previously installed app was not removed. Unlocking the iPad is required to complete installation; physical Pencil acceptance remains pending.

Physical installation retry succeeded: CoreDevice installed the signed Release build on the iPad Air (5th generation), installation sequence 3084, and launched `com.local.notesapp` successfully. This supersedes the locked-device installation blocker above. Hands-on Pencil and gesture acceptance is still pending; a successful launch alone does not validate those interactions.

## Discoverable toolbar organization — November 14, 2026

Named Draw, Study and Capture tile panels now occupy the former unused toolbar area; Laser and Zoom have direct buttons. Insert retains text/images/handwriting style. Stroke settings have a fixed-width home after the tools. Quick Adjustments exposes all three eraser modes. A single-tree SwiftUI Layout gives portrait/narrow headers a full-width tools row without State-driven header resizing or duplicate popover anchors. Top/bottom/left/right placement remains supported.

Validation: the two new organization tests cover complete, unique tool discoverability, contextual PDF availability, group presentations, and retained native canvas/content/Undo when changing tools. Fourteen targeted header/navigation/placement/native-button tests passed, then the complete simulator suite passed **174 tests with zero failures** (`/private/tmp/heynotes-toolbar-organized-full-tests.log`; result `Test-NotesApp-2026.11.14_22-32-00--0500.xcresult`). Tool grids and landscape/portrait editor screenshots were exported and inspected. Signed Release compilation succeeded (`/private/tmp/heynotes-toolbar-organized-release.log`). No metadata migration or file-storage change was made for this organization work.

The signed build installed successfully on the physical iPad, sequence **3092**, preserving the installed app's data container. Launch was blocked because the device was locked; unlock the iPad and open HeyNotes to inspect the new toolbar. Actual finger/Pencil feel remains a hands-on check. No commit or push was made.

## Icon-only toolbar refinement — November 14, 2026

Removed visible group/tool captions and the toolbar's Quick Adjustments ellipsis/popover. Panel titles, tool names inside panels, VoiceOver names and hover help remain. The color/width/settings control is compact; spare width shows favorite colors and, when space allows, width presets directly. The glass capsule hugs the actual controls instead of reserving a blank adjustment lane. Page Options remains separate beside the navigation controls.

Eleven targeted native tests passed (`/private/tmp/heynotes-icon-toolbar-final-tests.log`, result `Test-NotesApp-2026.11.14_22-56-16--0500.xcresult`). An actual raster regression checks that shrinking/growing favorite-control counts does not draw stale controls outside their reserved width. Dynamic ForEach ranges have explicit identity, preventing old colors from overlapping the palette after rotation. The obsolete ellipsis activation test was removed because that UI no longer exists; general native button/Page Options tests remain. Inspected final editor screenshots in both orientations. Signed Release compilation passed (`/private/tmp/heynotes-icon-toolbar-release-ready.log`). No persistence or metadata migration was needed, and no commit/push was made.

The first device install attempt encountered a transient connection reset. After refreshing device discovery, the final signed build installed successfully on the iPad (sequence 3104) and `com.local.notesapp` launched successfully. Existing application data was retained.

## Laser light appearance — November 14, 2026

Replaced the solid temporary laser line with a colored beam, thin white core, concentric translucent glow and a radial luminous pointer head. Core Animation updates avoid unnecessary full overlay redraws. Existing release fade/clear behavior and all persistence/export boundaries remain unchanged. Native light-renderer attachments were visually inspected over white/dark backgrounds and in red/blue. The 15 expanded-tool tests passed (`/private/tmp/heynotes-laser-glow-tests.log`), followed by the focused style/render check after aligning the light layer to overlay bounds (`/private/tmp/heynotes-laser-glow-final-check.log`). Signed Release build passed (`/private/tmp/heynotes-laser-glow-release.log`).

Installed successfully on the physical iPad, sequence 3120. Automatic launch timed out after 15 seconds; open HeyNotes manually to assess physical Pencil tracking and the light effect. No commit or push was made.

## Commit preparation — November 14, 2026

This delivery is organized into 29 scoped Conventional Commits on `feature/library-backups`. All 25 commits that contain app code or native source registration were compiled from their exact staged trees in an isolated snapshot directory before committing. The 50 host tests passed again. Splitting the history did not alter the implemented source files or discard pending work. Earlier entries saying no commit was made describe their original delivery sessions; this preparation supersedes that status. No push is included.

## Floating palette redesign — November 15, 2026

The favorites palette is now a 176 × 172-point floating tray for five/six favorites, with a shared profile/options header, six-dot grip, individual tool surfaces, inset color/width indicators and a 108 × 60-point collapsed pill. It uses the existing glass/Reduce Transparency policy. Profile/favorite data and normalized saved placement are unchanged. The rendered grid and native drop mapping share 44-point cells and 8-point gaps.

All 17 targeted palette/profile/drop/Focus Mode tests passed (`/private/tmp/heynotes-palette-redesign-final-tests.log`; result `Test-NotesApp-2026.11.15_00-04-32--0500.xcresult`). Inspected actual native Light, Dark/six-favorite and collapsed screenshots, plus the retained Focus Mode/edge-placement coverage. Signed Release compilation succeeded (`/private/tmp/heynotes-palette-redesign-release-final.log`) and the build installed on the iPad (sequence 3128). This design iteration is uncommitted; no push was made. Physical movement/drop feel remains a device acceptance check.

## Palette replacement drops — November 15, 2026

Toolbar/cross-profile tools dropped onto an occupied favorite now replace that slot, including at six-favorite capacity, preserving its ID and index. Empty-space drops still append only when there is room; same-profile drags still reorder. Target hover uses a stronger accent fill/border, glow and a small scale change that respects Reduce Motion. Only a completed drop persists the replacement. Late deleted targets reject safely, other profiles remain independent and active tool preferences are unchanged.

All 19 targeted native palette/profile/drag/Focus Mode tests passed (`/private/tmp/heynotes-palette-replacement-tests.log`; result `Test-NotesApp-2026.11.15_00-11-35--0500.xcresult`). Inspected the actual hover-style attachment. Signed Release build passed (`/private/tmp/heynotes-palette-replacement-release.log`) and installed on the physical iPad (sequence 3136). Physical drop/hover feel remains a hands-on acceptance check. No commit or push was made for this iteration.

## Individual palette destinations — November 15, 2026

A subsequent device report showed that the previous provider/model tests missed native destination routing: the palette still owned one container-level drop interaction with coordinate-based favorite lookup. Each favorite now owns its own native drop delegate with a permanent destination ID. The container is no longer a destination or highlighted. Only the hovered tool receives the accent border/fill/glow; releasing replaces that slot at six-favorite capacity. The + button remains an explicit append destination while space is available. No stored IDs, profile keys, document files or schemas changed.

The new `NotesAppUITests` scheme runs real system drags through normal app UI. It creates a QA notebook/profile in the simulator, fills all six favorites, then replaces each individual slot while checking stable IDs/order, unchanged siblings and a count of six. This passed (`/private/tmp/heynotes-palette-ui-test.log`; result `Test-NotesAppUITests-2026.11.15_00-29-04--0500.xcresult`). The test does not reset an existing store or require production launch hooks. Initial harness runs exposed inherited accessibility identifiers and duplicate toolbar/favorite labels; the final selectors distinguish the toolbar from favorite cells.

All 20 targeted native palette/profile/drop/Focus Mode tests passed (`/private/tmp/heynotes-palette-slot-tests.log`; result `Test-NotesApp-2026.11.15_00-30-46--0500.xcresult`). Inspected the final six-slot screenshot and frames from the actual drag recording: only the tool under the drag highlights, including when the drag crosses a different tool en route. Visual evidence: `/private/tmp/heynotes-palette-native-drag.mp4` and `/private/tmp/heynotes-palette-native-hover.png`.

Signed Release compilation passed (`/private/tmp/heynotes-palette-slot-release.log`). Installed on the physical iPad (sequence 3144) and launch succeeded. Physical finger/Pencil feel still requires hands-on acceptance; automated gestures were exercised on the simulator. No commit or push was made.

## Fixed tab-row save indicator — November 15, 2026

Moved the active document's aura dot from the tab title into a fixed 44-point control at the trailing end of the tab row. Its compact status popover reads the real session status and document title. The indicator follows split-pane focus, and the existing Focus Mode/error-alert behavior is unchanged. No save logic, schemas or document files changed.

All 10 existing tab-close, split-workspace and Focus Mode tests passed (`/private/tmp/heynotes-fixed-status-tests.log`; result `Test-NotesApp-2026.11.15_00-44-23--0500.xcresult`). Inspected the actual split-workspace screenshot with the dot at the trailing edge and no dots in tab titles. Signed Release build passed (`/private/tmp/heynotes-fixed-status-release.log`) and installed on the iPad (sequence 3152). No commit or push was made.

## Apple Pencil palette movement — November 15, 2026

The palette grip's pan recognizer explicitly excluded Pencil touches. Its allowed touch types now include direct touch and Apple Pencil; only the existing 44-point six-dot grip moves the palette. Existing active-stroke/busy guards, viewport clamping, cancellation and end-of-drag preference persistence remain unchanged. Updated the accessibility hint and interaction documentation.

All 14 existing palette, Focus Mode and page-gesture tests passed (`/private/tmp/heynotes-pencil-palette-tests.log`; result `Test-NotesApp-2026.11.15_00-47-03--0500.xcresult`). These are regression checks, not synthesized Apple Pencil contact. Signed Release build passed (`/private/tmp/heynotes-pencil-palette-release.log`) and installed on the iPad (sequence 3160). Manual device acceptance: drag the six-dot grip with Pencil and finger, cancel a drag, reopen/rotate and confirm the saved position, then write outside the palette in normal and Focus Mode. No commit or push was made.

## Integration into main — November 15, 2026

At the owner's request, local `main` incorporated the 29 existing `feature/library-backups` commits by fast-forward. The subsequent palette refinements/replacement fix, Apple Pencil grip support, native drag UI regression, fixed tab-row save indicator and their documentation are split into five additional scoped commits. Earlier “no commit” entries record the original delivery sessions; this integration supersedes their commit status. No push is included.

Each code-bearing staged tree was exported to an isolated snapshot and compiled before committing: palette, Pencil grip and save indicator app builds, plus build-for-testing of the dedicated native UI test scheme. Logs: `/private/tmp/heynotes-main-palette-staged.log`, `/private/tmp/heynotes-main-pencil-staged.log`, `/private/tmp/heynotes-main-ui-staged.log` and `/private/tmp/heynotes-main-status-staged.log`. These compilation checks supplement the runtime evidence above; they do not constitute another physical Pencil acceptance pass. Content hashes verified that splitting the commits did not change the implemented source files.

The experimental logo-inspired app/cover colors remain preserved separately in the paused `experimental` stash. App theme/accent files, cover models/renderers and bundled artwork are unchanged from pre-integration `main` (`d2ab170`). No user library, drawing, PDF or study data was modified by the Git integration.
