# Expanded student tools — implementation plan

Authorized November 14, 2026: implement all ten proposed tools, preserving the existing editor, palette, page gestures and offline operation. Work is incremental; no commit/push or cloud service is included.

## Delivery slices and acceptance

1. Selective highlighter eraser, transient laser, stamps, protractor/compass and foldable sticky notes. Reuse current drawing/object storage, apply explicit Undo, preserve non-marker strokes byte-for-byte, keep transient guides out of saved/exported content.
2. Hold-to-snap shapes. Observe Pencil input without blocking native ink; recognize conservative line/rectangle/ellipse candidates after a hold, preserve original ink and reject stale page/stroke results.
3. Region capture and PDF text highlighting. Share page/export geometry, bound image resolution, use original selectable PDF text, reject scanned/no-text selections explicitly, and never mutate source PDFs.
4. Region flashcards. Freeze the currently shipped V6 schema before adding optional question/answer image paths in V7. Test lightweight migration against a genuine V6 store. Persist immutable card images before a single metadata save. Keep captions and permanent source page IDs; handle missing images without blocking study. Extend complete-library backup capture/validation/restore to cover card image assets and refuse unsupported newer record formats.
5. Zoom writing window. Keep one canonical page drawing and checkpoint path; disable simultaneous overview writing, capture the zoom canvas on save/background, preserve page/session identity, and register useful Undo checkpoints. Close/rebind safely on page changes.
6. Full validation: legacy metadata/object/preference decoding, migration, undo/reopen, source PDF immutability/rotation, annotation and margin export, capture bounds, card image backup/remapping, tool/palette state, frame/memory behavior and all existing native regressions. Physical Pencil gesture feel remains a device acceptance check.

## Persistence design before modifications

Page objects retain their existing kinds. Sticky notes add optional text-object style/fold state; highlights add an optional filled-rectangle flag. Missing optional properties decode to legacy behavior. Stamps are ordinary editable text objects. Compass circles are ordinary editable ellipse objects. Existing immutable image storage and PDF rendering/export are reused.

V6 is frozen in a separate schema snapshot with all seven existing entities and relationships unchanged. V7 adds only two optional relative image paths to Flashcard; existing cards retain nil images and identical IDs, source links, history and due dates. Old migration stages remain immutable. Backup record version 2 will include these optional image references, accept old version-1 backups, and validate/rewrite all referenced files on additive restore. No automatic purge is introduced.

Smart-shape conversion stores the removed source ink on the resulting editable object and uses the editor's combined ink/object Undo boundary. Selective erasing removes complete intersected highlighter strokes in its first implementation; precise partial erasing remains the existing standard eraser mode. PDF highlights are independent per-line filled objects above the immutable PDF background. Geometry tools measure logical page points/degrees, not calibrated physical millimeters.

Toolbar growth stays bounded: group measurement/drawing controls, insertion/capture tools and reading/study tools in the existing menus. Saved presets carry relevant settings; quick palette remains six favorites per profile. Temporary selection/laser/measurement state is scoped to a visible page and never exported as saved content.

## Implemented controls

The toolbar keeps direct writing/selection controls and adds icon-only **Draw**, **Study**, and **Capture** groups with labeled tile popovers, plus direct **Laser** and **Zoom** icons. Compact settings and direct favorite colors/widths occupy the remaining space; the toolbar has no adjustment ellipsis. Narrow/portrait headers use a full-width tool row. See [ToolbarInteraction.md](ToolbarInteraction.md) for the current organization. Each tool is also available in the existing Quick Palette preset editor; presets retain stamp symbols, sticky-note colors and selective-eraser settings.

1. **Highlighter-only eraser:** select Eraser, then its settings → Highlighter Only. Touching a marker stroke removes the entire visible stroke. Pen/pencil strokes, distant markers and unrelated object content remain untouched. Native whole-stroke and precise erasers remain available. Discrete PDF text highlights are objects; edit/delete those through Select Objects or Inserted Content.
2. **Hold to Snap Shapes:** enable the toggle in Draw. Draw a line, rectangle or ellipse with Pencil, pause for about 0.4 seconds to see the dashed candidate, then lift. Uncertain or tiny shapes stay ink. Converted shapes remain editable objects; Inserted Content → Restore Original Handwriting recovers the source strokes. Conversion is one ink/object Undo action. Finger input does not snap in this implementation.
3. **Laser pointer:** Laser on the toolbar. Draw or tap with Pencil; each completed stroke stays fully visible for three seconds after lifting, then fades over 0.6 seconds. New strokes do not replace earlier ones. Color, thickness and opacity are configurable. Laser trails never enter a drawing, backup, thumbnail or exported PDF.
4. **Stamps:** Study → Stamp; choose Check/Cross/Star/Question/Important in its settings. Tap to place, then use Select Objects to move/resize. Stamp text, color and size remain editable through existing object editing.
5. **Protractor and compass:** Draw → Protractor / Compass. For angles, tap the vertex and a point on each arm; the fourth tap resets. The guide is temporary. For circles, drag from the center to set the radius; lifting inserts an editable ellipse. Radius is clipped to the page and measured in logical points, not physical millimeters.
6. **Foldable notes:** Study → Sticky Note, then tap a location and enter text. Finger-tap the note header to fold/expand; use Select Objects for position/size and Inserted Content for text/color. Folding preserves the complete text and original expanded rectangle. PDF exports reflect the current folded state; expand a note before exporting its full body.
7. **Region capture:** Capture → Capture Region. Drag across the page with Pencil. The preview offers actual PNG copy/share, reinsertion as an independent image, or creation of a flashcard. Captures include the page background/PDF, ink, objects and covered study tape; they do not remove or modify source content.
8. **Image flashcards:** choose Study → Flashcard (the first region is the question), then select question/answer areas on the captured page. Alternative Whole Page/Top Half/Bottom Half buttons avoid requiring precise dragging. Choose an existing deck or create a notebook-linked deck. Optional descriptions improve identification and VoiceOver. Captured image faces work with the existing scheduled/practice review, ratings and Open Source Note. Missing images show a recoverable message without deleting cards or their source links.
9. **PDF text highlight:** Capture → PDF Highlight. Pencil-drag a region; each selected text line becomes an independent translucent rectangle in the same normalized crop/rotation geometry as the displayed page. This requires selectable PDF text, does not perform OCR and does not rewrite the source document. Selecting a blank note margin or a scanned/no-text region shows a message.
10. **Zoom Writing:** Zoom on the toolbar, then Pencil-drag a region. The bottom writing window magnifies that region while a dashed guide remains on the full-page overview. Pen, pencil, marker, standard eraser and native lasso work inside the window. Use two fingers to pan; arrows move the writing origin and Return advances down the page. Close returns to normal writing. Selecting an object/auxiliary tool closes the window after a successful save.

Pencil is the default for region drags and the compass; the existing Draw with Finger setting also enables direct-touch drags. Ordinary one-finger page navigation remains available when not drawing with a finger. Taps used for stamps, notes and measurement also accept a finger.

## Window, history and save boundaries

`ZoomWritingHost` owns a second native canvas with the **same logical coordinates and PKDrawing**. It is not a duplicated page or a raster simulation. While open, overview handwriting is disabled. Native window changes update the canonical drawing and overview, and the existing debounced checkpoint writes the same per-page path. Explicit save/background/export/page-switch boundaries read the live window canvas before queued delegate notifications. Page identity guards reject outgoing callbacks. Failed saves retain the window, pending native ink and retry message.

The window has native per-stroke Undo while open. Closing it retains the entire writing-window session as one Undo action on the main page canvas. This avoids losing the window's edits when the secondary view is disposed. Handwriting-style conversion is paused while the window is open to avoid two processors rewriting the same live drawing; close the window before explicitly converting handwriting.

## Files and resource limits

- `StudentToolGeometry` and `SmartShapeGeometry` contain platform-independent tool geometry and shape recognition.
- `StudentToolOverlay`, `MeasurementToolRenderer`, `ShapeHoldObserver`, `ShapeHoldTracker` and `SmartShapeCoordinator` handle transient native input/feedback.
- `EditorStudentTools`, `EditorSmartShapes`, `EditorCapture` and `EditorZoomWriting` own editor operations and identity/Undo guards.
- `PageCaptureService`, `StudyCaptureImages`, `ToolCaptureFlow`, `RegionFlashcardForm`, `RegionSelectionCanvas` and `StudyAttachmentImage` provide real image creation, storage, editing and review presentation.
- `PDFTextSelection` reads selectable text using the existing PDF service actor.
- `SchemaV6`, the V7 live model and backup format 2 carry the optional relative card image paths. Assets are immutable `Study/Images/<UUID>/Question.png` and `Answer.png` files.

Capture first flushes native ink, renders through the existing export worker, bounds the image to 2048 pixels on its longest edge (up to 2× logical resolution), then crops on an actor. Reinsertion reuses existing bounded image import. Region crops are snapshots and do not track subsequent changes to the original note. Original page links remain permanent UUIDs. Failed metadata saves may retain unreferenced immutable image bytes for recovery; no automatic destructive cleanup is introduced.

Native overlays use bounded backing scales, matching the existing 2400-point backing limit for large pages. No laser frames or freehand movement are persisted. Expensive marker filtering, PKDrawing serialization, PDF rendering and image cropping run away from the main actor. Main-actor native drawing/model operations remain necessary.

## Device acceptance

Automated tests cannot establish actual Pencil latency or gesture feel. On a physical iPad, verify Pencil-only writing, a held shape and recover/Undo, selective erasure over pen/marker overlap, laser fading, finger paging with every new tool selected, note folding, PDF text selection, question/answer crop gestures, and writing-window pan/Undo/background/relaunch. Include both orientations, Draw with Finger, Focus Mode and a split workspace. No cloud account or network connection is needed.

## Verification evidence

On November 14, 2026, Xcode 27.2 / Swift 6.4.2 compiled this implementation with deployment target iPadOS 17. The host suite passed **50 tests**, including a genuine on-disk V6 → V7 migration, preserved file bytes/source IDs/review progress, old object decoding, shape geometry, image-card backup round trips, legacy version-1 restore and missing-image rejection. The complete native simulator suite passed **172 tests**, including **15 new tool tests**. Existing page-turn, split workspace, Pencil double-tap, palette, toolbar, export, Study and persistence regressions remain covered.

New native cases verify transformed/masked marker filtering with unchanged non-marker stroke content, Undo/reopen, original-ink recovery after shape snapping, stale-page rejection, folded-note/stamp persistence/export, cropped/rotated PDF text bounds against actual rendered dark pixels, blank-margin rejection, bounded real PNG crops, image-card edits/review persistence, live zoom-canvas flush without delegate delivery, clear/Undo synchronization, failed-save retention and correct page-switch destinations. Visual attachments cover question/answer crop creation, image review, rotated text highlighting, and the writing window with its page overview in both orientations.

The crop/rotation fixture is serialized and reopened before raster comparison, matching production import. Mutating PDFKit's in-memory page rotation/crop and immediately reusing its old `pageRef` does not produce a reliable reference raster. Tests compare public stroke content when constructing new PKDrawing containers, because PKDrawing equality also includes container identity. Hosted test fixtures retain their in-memory model containers through asynchronous SwiftUI teardown.

The writing guide marks the selected region; manual two-finger panning can reveal surrounding content. The window fits the complete selected rectangle and its controls move that selection. A focused native rerun checks the final fit/centering refinement after the complete regression pass. Signed Release builds also succeed. Automated evidence does not replace the physical Pencil acceptance checks above.

## Luminous laser refinement

The temporary laser now has a narrow colored beam, a bright white core, translucent concentric glow strokes and a radial light at the current pointer position. It respects the saved laser color/width/opacity independently of pen settings. Each completed stroke holds for three seconds, then all its parts fade together over 0.6 seconds. Writing the next stroke leaves previous strokes and their independent deadlines intact. Style changes preserve released strokes' colors. Switching tools/pages or cancelling input clears the lights and their pending cleanup tasks. This is still a transient overlay and never enters drawing, image-card, backup or export data.

`LaserPointerVisual` owns temporary per-stroke lights and their cleanup tasks. Each light uses a small set of Core Animation vector layers and a radial-gradient head. It uses no page-wide blur filter and disables implicit animations on pointer updates. Laser movement no longer requests an unnecessary full overlay redraw; geometry/capture/eraser feedback retains its existing drawing path. Native snapshots of the actual layer renderer were inspected in red/blue over white paper and red over a dark background. All 15 expanded-tool native regressions pass (`/private/tmp/heynotes-laser-glow-tests.log`); the final layer-bounds refinement receives a focused style/render check. Physical Pencil tracking and perceived glow remain device acceptance checks.


## Hold-to-snap reliability refinement — November 16, 2026

Shape capture now consumes actual coalesced, precise Pencil samples. A bounded tracker measures pause movement in window points, so the six-point pre-snap jitter radius and twelve-point preview hysteresis feel the same at fitted and high zoom. The pause is 400 ms. Moving farther resumes capture and rearms recognition; lifting before a successful pause keeps native ink. Input is bounded to 4096 samples, decimating older samples as necessary while retaining the gesture's endpoint. Predicted touches are not used.

Recognition resamples the path at 96 evenly spaced arc-length positions, removing sensitivity to corner dwell and uneven drawing speed. Line fitting uses a principal axis and straightness/path-length checks, with near-horizontal/vertical alignment. Rectangles require perimeter travel, all four corners and edge proximity; ellipses require radial fit and coherent, nearly complete angular coverage. Small closure gaps and modest wobble are tolerated, while open curves, double loops, unsupported polygons and obvious zigzags remain ink. The minimum size is supplied in logical page coordinates from a 24-screen-point threshold, so small writing at high zoom is eligible without changing page geometry. Supported results remain lines, axis-aligned rectangles and circles/axis-aligned ellipses; this does not add triangles, rotated-shape metadata or arrow recognition.

Completion is coordinated across observer lift, native tool end and committed drawing notifications in any order. It waits for the expected extra stroke and schedules at most one replacement. Repeated attachment of an already enabled observer no longer resets its hold; the color/width/opacity are captured at stroke start. Backgrounding, disabling/changing the tool, detach, a new stroke or stale page invalidate pending conversion. Preview paths disable implicit layer animations. The observer never prevents or delays PencilKit or changes the page's zoom.

New snapped objects store their initial object position as an original-ink anchor. Restoring an unmoved shape therefore preserves the exact source stroke coordinates; moving the object translates its restored ink by the same amount. The existing archive, per-page persistence and compound Undo/Redo remain in use. No schema migration or external service is introduced.

Automated tests exercise noisy/nearly closed and unevenly sampled shapes, small zoom-scaled geometry, sparse/wobbly lines and rejection cases; native tests cover jitter, hold cancellation/rearming, all completion orders, repeated callbacks/attachment, starting style, background/stale-page/disabled rejection, exact original-ink recovery, editable persistence and one-step Undo/Redo. Real Pencil recognition feel remains physical-device acceptance.

Apple references: [coalesced touches](https://developer.apple.com/documentation/uikit/uievent/coalescedtouches(for:)), [high-fidelity input](https://developer.apple.com/documentation/uikit/getting-high-fidelity-input-with-coalesced-touches), [PencilKit drawing events](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdelegate).
