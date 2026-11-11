# Phase 2 — editor verification

## Results in the development environment

- PASS: simulator app build (Swift 6, deployment target 17.0).
- PASS: 9 host tests across 3 suites.
- PASS: 3 native XCTest tests on iPad Pro 13-inch simulator, iPadOS 26.5.
- The earlier Phase 1 simulator access restriction was resolved by authorized execution outside the workspace sandbox. No compiler sandbox override is persisted in the project.
- Real Apple Pencil hardware acceptance remains pending.

## Automated coverage

Host tests (`swift test`) exercise real SwiftData and filesystem behavior: reopening stored metadata, relationship deletion, page ordering and normalization, notebook copies with independent drawing paths, missing files, atomic replacement, backup restoration, write errors, path traversal and symlink rejection.

Native `NotesAppDeviceTests` uses actual PencilKit: nonempty PKDrawing round trips, immediate page-switch flush before debounce, page duplication, corrupt-page protection, validated backup restoration and save failures blocking navigation while retaining pending ink. Run with the NotesApp scheme and ⌘U on an iPad simulator. These tests do not replace hardware Pencil testing.

## Manual acceptance on a physical iPad

1. Run NotesApp with ⌘R, select your iPad as destination. Open an existing Phase 1 notebook; verify its title, cover and paper selection remain intact.
2. Draw fast/slow strokes with Apple Pencil using pen and highlighter. Try each width and ink color. Use eraser, lasso move, undo and redo. Check palm rejection and latency with a full page of ink.
3. Pan with one finger and pinch to zoom. Confirm ink and ruled/grid lines remain aligned. Rotate and resize; zoom out and verify the complete page remains reachable.
4. Draw, immediately add/switch pages, return, and confirm the latest stroke is there. Duplicate a page and change only the copy. Move pages in both directions, delete a middle page, relaunch and confirm contiguous ordering and independent ink.
5. Leave via Library immediately after drawing, then reopen. Repeat by sending the app to the background. Relaunch after the status says Saved on iPad and verify the drawing.
6. In Page Options change among blank, ruled and grid paper without losing ink. Enable Draw with Finger, draw with touch, pan with two fingers, then turn it off.
7. Duplicate a handwritten notebook in Library. Edit/delete the copy and verify the original remains unchanged.
8. Use an expendable test notebook for recovery: make at least two saves, corrupt the live `.drawing` through the app's simulator container, reopen, and verify editing is blocked. Restore Backup; verify prior ink returns and a `.damaged-<UUID>` file preserves the corrupt bytes. A missing file with no backup must stay an error.
9. Enable VoiceOver and large Dynamic Type. Verify tools have names, thumbnails identify selected page and template, and the horizontally scrollable toolbar remains reachable. Paper remains white even with system dark mode.

## Known limits

- Real Apple Pencil latency, palm rejection, gesture arbitration and lasso/undo behavior require the manual hardware checks above.
- No persistent undo history across page switches, custom page dimensions, automatic orphan cleanup or deleted-page browser.
- Backups preserve the previous successful checkpoint, not an unlimited revision history. Files retained after deletion consume space.
- The live drawing snapshot is kept after a save failure. Keep the editor open and retry. A forced process termination before a successful checkpoint can lose the latest changes.
- PDF import/export and study features are not part of this phase.

## Device delivery

The Phase 2 device build passed with the existing development team and signing settings. The signed update was installed over `com.local.notesapp` on the connected iPad Air (5th generation), and CoreDevice confirmed a successful launch. This verifies delivery and process launch, not Apple Pencil interaction. The metadata schema and bundle identifier remain unchanged.


## Compact page navigation refinement

The always-visible 128-point thumbnail strip has been replaced by a 52-point bottom bar at standard text size. It provides previous/next, current page / total count, and a 44 × 44-point Add Page button. Tapping the counter/grid icon opens a scrollable thumbnail popover, so previews consume canvas space only when requested. Save-before-navigation behavior is unchanged.

Manual check: open a multipage notebook, use arrows and the thumbnail popover, add a page with +, and verify first/last-page arrow availability. Test portrait, landscape and large Dynamic Type. The compact bar frees 76 vertical points at standard text size.


## Single-row editor header

The notebook title is now leading-aligned beside Back to Library. Drawing tools sit to its right in the same header row, followed by Page Options. The separate centered navigation title and second toolbar row are removed. Long titles truncate to preserve tool space; tools remain horizontally scrollable in narrow windows. Save status uses a compact icon with a full VoiceOver label. Validate long titles, portrait/landscape, narrow windows and returning to Library on a physical iPad.


## Finger page turns at full-page zoom

At minimum zoom, a short intentional flick turns existing pages without dragging the sheet across the viewport. A slower swipe also works at a reduced distance. Flicking left at the last page does not add anything: pull left farther and keep holding for 0.5 seconds to create one page. A temporary progress indicator shows the countdown. Lifting early, reversing, a second finger, zooming, Pencil input or loss of the active editor cancels the pending hold. Top Add Page remains immediate.

Direct-touch and fit-to-page guards, Draw with Finger arbitration, stable page UUIDs and save-before-navigation remain in place. Creation is explicitly disabled for ordinary swipe callbacks and enabled only by a completed, single-commit hold. See [current gesture policy, thresholds and tests](PageGestures.md). Hardware gesture arbitration and feel still require iPad acceptance.


## Directional page transitions

Page changes keep the old canvas on screen until file loading finishes. A clipped viewport then uses a short directional offset and crossfade for 140 ms, preserving real PencilKit rendering rather than rasterizing ink. The viewport and controls stay visually stable while loading; finger paging remains available while Pencil ink pauses briefly during the motion. Forward pages enter from the right; backward pages enter from the left. Reduce Motion replaces the page directly without movement or fading. Pencil drawing pauses for the turn, rapid finger navigation completes the previous transition before starting the next, and viewport resizing finishes any pending transition.

Late drawing delegate callbacks are checked against the active page UUID. An outgoing canvas can never apply its drawing to the destination page. Save failures still block navigation. Test swipes, arrows, thumbnails and adding a page; repeat with ink-heavy pages, rapid navigation, orientation changes and Reduce Motion enabled on the physical iPad. Animation smoothness remains a hardware acceptance check.

Transition validation: device build passed; all 5 native tests passed on an iPad Air 11-inch simulator, including assertions that a late callback from the outgoing ink canvas cannot overwrite the new page. One earlier simulator run failed before test execution because the simulator reported Busy during launch; retrying on the iPad Air simulator succeeded. Animation smoothness and Reduce Motion appearance still need physical-device review.
