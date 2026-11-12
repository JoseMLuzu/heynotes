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
