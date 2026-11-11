# Student tools

Implemented inside the existing SwiftUI/PencilKit editor. Flashcards (item 7) and content/handwriting search (item 8) remain deferred. Everything works locally; there are no external services or new dependencies. Minimum deployment remains iPadOS 17 with Swift 6.

## Using the six tools

1. **Study tape:** select the filled rectangle tool, then drag across an answer with Apple Pencil. Return to a writing tool and tap the tape with a finger to reveal/cover it. Reveal state resets when reopening the page. Select Objects moves/resizes tape; Inserted Content edits or deletes it. Pencil input continues to reach PencilKit in writing mode.
2. **Ruler and shapes:** the ruler button toggles PencilKit's public native ruler. Shapes and Arrows opens line, rectangle, ellipse and arrow tools. Drag with Apple Pencil to create a vector object; color, opacity and width use the ink settings and can be saved in Quick Palette presets. These are explicit shape tools, not automatic handwriting recognition. Shapes/text/images sit below handwriting; tape sits above it.
3. **Named bookmarks:** tap the dedicated bookmark button beside the page counter to immediately add/remove a bookmark on the current page. New bookmarks receive a Page N name. Open the page index and its labeled Bookmarks filter to browse saved pages or edit their names. The same menu renames/removes bookmarks. References use permanent page UUIDs.
4. **Notebook sections:** in the page index, use + → New Section. Section menus rename/reorder groups or move the current page into them. Thumbnail menus move any page to another section or Unsectioned Pages. Deleting a section requires confirmation and retains all its pages. Existing page duplicate/delete/reorder actions remain in Page Options.
5. **PDF note margins:** open a PDF page and choose Page Options → PDF Note Margin. None/Small/Medium/Wide adds 0/25/50/100 percent of the original width on the right. The source PDF keeps its dimensions and coordinates. Export includes the entire expanded page. Reducing a margin is rejected if it would clip handwriting or inserted content; move that content inward first.
6. **Typed text and images:** Insert (+ in a square) adds typed text or an image from Photos/Files. Text supports system font size and color. Select Objects moves inserted objects; its bottom-right handle resizes them. Inserted Content offers precise editing and confirmed deletion. Object operations participate in the current canvas undo/redo session.

All controls stay at the top. The toolbar scrolls horizontally in constrained windows; narrow iPad windows use a second top row. The bottom remains clear. Quick Palette profiles can also contain shape/tape/object tools.

## Export behavior

Page Options explicitly offers notes **Without Study Tape** and a **Practice (Covered)** copy, for either the current page or whole notebook. Practice export always covers answers, regardless of temporary reveal state. Normal export includes the original note content without the covers. This is a study aid, not secure redaction: covered text can still exist in the PDF text layer.

The export worker renders source PDFs at their original normalized crop size, then inserted content, ink and optional tape. Text and shapes use Core Text/Core Graphics; image files are resolved strictly and decoded per page inside an autorelease pool. A missing image fails export with an error rather than silently omitting content. Source PDFs and editable drawing files are never rewritten by export. Existing PDF flattening/ink-resolution limitations in Phase3.md still apply.

## Data, migration and reliability

The exact previously shipped V3 model is frozen in `Core/Persistence/SchemaV3.swift`. Current metadata is NotesSchemaV4 with lightweight V1 → V2 → V3 → V4 migrations. Startup never deletes/recreates a store after migration failure.

- Notebook gains `sections`; NotebookSection stores UUID, title, sortIndex, optional notebook and inverse pages.
- NotePage gains optional bookmarkTitle, section, objectsData and pdfRightMargin. Existing pages default to no bookmark/section/objects/margin. Existing UUIDs, drawing paths, PDF references and original dimensions stay intact.
- Objects use a versioned Codable envelope with permanent IDs, finite validated geometry and relative image paths. Unsupported/damaged envelopes produce a page error and preserve their bytes; they never become writable empty content.
- Images are downsampled off MainActor to at most 2000 pixels on the longest edge and saved as private JPEG files. Transparency/animation/Live Photo metadata and original image resolution are not preserved. No broad Photos-library access is requested.
- Binary image writes finish before metadata references are saved. Whole-notebook duplication copies immutable image assets into the new notebook, deduplicates repeated source references and generates new object/section/page UUIDs. Page duplication within a notebook shares immutable image bytes while keeping independent object metadata. Moving notebooks only changes folder metadata.
- Small object/bookmark/section mutations explicitly save metadata. Drag previews remain transient until gesture completion; PencilKit keeps its existing debounced, atomic per-page save/flush pipeline. Invalid object changes roll back without replacing saved content.
- Sections group pages into one stable global order, followed by unsectioned pages. Section moves normalize pageIndex without changing page UUIDs. New pages inherit their current section and full visible dimensions. Duplicated PDF pages preserve their source geometry and note margin.
- Missing/corrupt drawings, PDFs or image assets block editing rather than silently discarding content. Backup recovery validates inserted content before restoring ink. Failed imports/metadata operations and deleted objects can leave retained private asset files; no automatic orphan purge runs.

## Verification

Host tests cover a real frozen V3 store migrating to V4, prior migrations, page identity/order, section removal, bookmarks/content after reopening, and independent notebook/image duplication. Native tests cover object undo/redo, temporary tape reveal, invalid envelopes, ruler/presets, section commands, native editor rendering, and extended PDF export with text/shapes/images/tape plus original-source byte preservation. Existing drawing, gesture, workspace, template, palette, storage and PDF regression suites also run.

Manual iPad acceptance:

1. Open an existing notebook after updating; check ink, covers, folders and page order.
2. Add tape over real handwriting, switch to pen, reveal with a finger and continue writing with Pencil. Test zoom and two-finger panning in object mode.
3. Create shapes and a ruler line. Move/resize objects and undo/redo. Switch pages, relaunch offline and verify content.
4. Add/rename/reorder sections, move pages, bookmark one and navigate through the filter. Delete a section and confirm its pages remain.
5. Import a PDF, add a right margin and write across both regions. Export normal/practice copies and compare source dimensions, annotation alignment and the unchanged original file.
6. Insert Photos/Files images and typed text, duplicate a notebook, edit the copy and verify the original remains unchanged.
7. Check portrait/landscape, resizable windows, dark mode, Dynamic Type and VoiceOver. Real Pencil latency and minimum-OS runtime validation still require physical-device review.

Incremental limits: no OCR/automatic shape recognition, arbitrary page rotation, rich text, image crop/rotation, automatic margin-content relocation, persistent cross-page undo history, or secure document redaction. Object editing is separate from PencilKit's ink lasso. Flashcards and handwriting/content search are not implemented in this delivery.

## Executed validation — 2026-11-09

- PASS: 22 host tests in 9 suites, including a real V3 → V4 store migration, persisted section/bookmark/object data and independent image duplication.
- PASS: 47 native tests on iPad Pro 13-inch (M5), iPadOS 26.5 simulator; no failures. Editor and practice-export screenshots were visually inspected. Tests retain these attachments in the Xcode test result.
- PASS: signed generic iOS build with existing team 62TPVT35FP and bundle identifier com.local.notesapp. No new OS 27-only API requirement was introduced.
- Device installation was attempted but CoreDevice reported error 4016: the paired iPad Air was unavailable and could not satisfy connectivity/service assertions. The existing installed app and its data were not removed. Connect/unlock the iPad, select NotesApp and that iPad in Xcode, then press Command-R. Actual migration of the user's private on-device library remains to be checked there.

## Navigation and library refinements — 2026-11-09

At full-page zoom, a horizontal finger swipe now changes pages with shapes, arrows, tape and object selection active. Object creation uses Pencil by default. In Select Objects, a finger drag beginning on an existing object (including its resize handle) edits that object instead of turning the page; swipe over empty page space to navigate. Two fingers pan while editing objects. Enabling Draw with Finger explicitly allows finger creation and keeps the existing no-swipe policy for that mode. The last-page 0.5-second hold-to-create behavior is unchanged.

Bookmarks have a dedicated 44-point top button and a filled state for the current bookmarked page. The button now toggles only the current page; browsing and renaming remain available in the page index.

Library folders now share the notebook grid, portrait cover aspect ratio and caption layout. Folder artwork uses a native folder tab and paper treatment. Both item types reserve two title lines below the cover, and grid columns align items at the top; long titles no longer move the covers upward. Folder navigation and existing context menus remain intact. No metadata schema change is involved.

Validation: 48 native simulator tests pass, including direct-touch routing through the real page gesture delegate for all six object tools, preserved object dragging, zoom/finger-drawing exclusions, and existing save/navigation regressions. Library and editor screenshots were visually inspected. The signed generic iOS device build passes.

## Direct bookmarking and save indicator — 2026-11-09

The top bookmark button immediately marks/unmarks the current page without opening a browser or asking for a name. A new bookmark uses Page N; existing named bookmarks can still be edited through the index. The button's VoiceOver label describes the current add/remove action.

The checkmark/manual-save control is removed from the tool strip. A small noninteractive status dot at the far right of the editor header is blue when the page is loaded and saved, and orange while handwriting has pending changes, writes are in progress, or the page is unavailable. Pending state is retained on save failure and only clears after the latest revision commits successfully. The indicator exposes the actual status through VoiceOver and help text. Save Now remains in Page Options; drawing-save errors offer Retry Saving. This represents local persistence, not cloud synchronization. Existing debouncing and navigation/background flushes remain unchanged.

Validation: all 48 native simulator tests pass, including pending-state checks for concurrent flushes, debounced saves and write failure.

## Compact right-side controls — 2026-11-09

The editor header now groups only the direct bookmark toggle, page counter and options ellipsis in one quiet surface. Tapping the counter opens the page index. Add Page and Show/Hide Quick Palette are in the options menu, with Restore Quick Palette Position kept reachable there as well. The index + action and 0.5-second last-page hold are unchanged. Export variants are grouped in an Export PDF submenu. The status dot stays at the far-right corner. A native editor rendering test and the signed generic iOS build pass.

## Final annotated layout — 2026-11-09

Following the annotated iPad screenshot, the main page menu moves to the top-right of the document-tab row; Recently Opened is included there. Tabs divide available width equally and scroll once their readable minimum cannot fit. The left tab-row button toggles the sidebar. The save dot returns beside the title. The palette launcher is pinned at the end of the tool strip. Bookmark and page-index controls remain at the lower row's right. Tools follow a fixed task-based sequence (writing/eraser, settings, selection, shapes/tape/insertion, undo/redo); ruler moves into Shapes. This supersedes the earlier compact-header placement notes. No data migration or usage-statistics collection is involved. See Workspace.md for layout validation.

## Glass toolbar — 2026-11-09

The document name appears only in the tab, freeing the left side of the editor. Tools and page controls use capsule-shaped glass surfaces, with circular selection highlights. Native glass is availability-guarded for iPadOS 26; earlier supported versions use Material, and Reduce Transparency uses an opaque surface. The save dot remains visible beside the back control. Tool order, palette recovery, page navigation and local save behavior are unchanged.
