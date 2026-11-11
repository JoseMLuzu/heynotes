# Architecture and delivery plan

## Product boundary

An iPad-only study notebook: Write. Study. Remember. Purchase-once pricing is a future product decision; the MVP has no store integration. Everything remains local. UIKit is used only through native platform integration where SwiftUI needs PencilKit, PDFKit or sharing.

## Decisions in Phase 1

- **iPadOS 17 minimum:** SwiftData and Observation establish the baseline. Swift 6 language mode is independent of the OS version. Building with SDK 27.2 does not opt the app into 27-only APIs.
- **Light MVVM:** LibraryViewModel owns metadata operations. Views own transient presentation and navigation state. ModelContext remains on MainActor. Metadata writes are small synchronous transactions; binary I/O in later phases belongs off MainActor.
- **Explicit persistence:** save after every user mutation, disable context autosave, roll back on failure and report the error. No fabricated data or in-memory fallback if the real store fails to open. The startup error view preserves the original store.
- **Relationships rather than duplicate IDs:** SwiftData inverses represent folderId and notebookId. Page order comes from pageIndex, never the persisted relationship array order. UUID breaks accidental index ties deterministically.
- **No speculative service layers:** storage and export protocols will appear with their first implementations. There is no empty service or no-op feature claiming to work.
- **Local configuration:** CloudKit is explicitly disabled. SwiftData manages its normal on-device Application Support store. Drawing paths will be relative to an app-managed document root, not absolute sandbox locations.
- **One app window:** avoids conflicting canvas writers before a coordinated multi-window document strategy exists. Split navigation still adapts to portrait and narrow windows.

## Initial implemented schema

| Model | Stored fields | Relationships and lifecycle |
| --- | --- | --- |
| Folder | unique UUID, title, createdAt | notebooks; nullify on folder deletion |
| Notebook | unique UUID, title, createdAt, updatedAt, coverColorRawValue, isFavorite | optional folder; cascade pages on explicit notebook deletion |
| NotePage | unique UUID, pageIndex, paperTemplateRawValue, optional drawingFilePath, createdAt, updatedAt | optional notebook inverse; each page will own its own drawing file |

`coverColor` and `paperTemplate` are typed accessors backed by string values. Unknown values display a safe default without rewriting their stored raw value. All creations use new UUIDs. A fresh notebook has one real page record and no drawing file. Duplication currently copies blank page metadata; notebooks with non-nil drawing paths cannot be duplicated or deleted until file lifecycle support is implemented. This prevents a later partially implemented feature from sharing ink files or silently orphaning/deleting data.

There is no schema version migration plan yet because this is the first development schema. Before shipping or modifying a user-visible schema, introduce VersionedSchema / SchemaMigrationPlan, preserve the existing version, and test reopening older stores. Do not use deletion/recreation as migration recovery.

## Planned schema additions (not implemented)

| Model | Fields / references | Integrity policy |
| --- | --- | --- |
| ImportedPDF | UUID, notebook relationship, relative original PDF path | private immutable copied original; validate before committing |
| PDF page metadata | source PDF page index, dimensions, crop/rotation transform, optional margin width | page-specific ink uses the same page coordinate system as export |
| StudyDeck | UUID, title, optional notebook reference, createdAt | notebook deletion detaches deck, preserving cards |
| Flashcard | UUID, deck relationship, question, answer, optional sourcePage reference, createdAt, updatedAt; nextReviewAt and scheduling state | page deletion detaches source; deck deletion requires confirmation and cascades cards |
| ReviewRecord | UUID, card relationship, reviewedAt, rating, nextReviewAt | append review event and update card scheduling state in one metadata save |

Do not persist a derived notebookId alongside a notebook relationship. A card's source link resolves its notebook through NotePage. Missing/deleted sources show an explanation; never navigate to another page silently.

## Future file lifecycle and performance

Layout: `Documents/Notebooks/<notebook UUID>/Pages/<page UUID>.drawing` and a private copied PDF under the notebook directory. Store relative paths. A future storage actor validates paths, serializes per-file writes and uses atomic replacement; an immutable save snapshot crosses the actor boundary, not a SwiftData model or live PKCanvasView.

SwiftData saves and filesystem writes are not a shared transaction. Create files before linking metadata; only clean up files created by a failed operation. Duplicate files to new IDs before saving duplicate records. Use a staged trash/journal and recovery path for deletion, and reconcile interrupted operations. Never treat a corrupt/missing drawing as an empty page and overwrite it. Avoid loading all page drawings when listing a library. Phase 1 fetches all small metadata records; profile and introduce paginated queries if real libraries justify it.

The editor needs a per-page debounced save coordinator, revision ordering, dirty state, and explicit flush on navigation/background. Canceling a debounce must not discard its most recent snapshot. Return from page navigation only once pending writes succeed or after an explicit recovery decision. iPadOS can terminate a process without a final callback: short debouncing and frequent safe checkpoints reduce loss; an unconditional guarantee on force termination is impossible.

## Risks and verification

| Risk | Mitigation / acceptance evidence |
| --- | --- |
| Pencil latency and gesture conflicts | MainActor canvas only, binary work off main; Pencil-only drawing policy, finger pan; test real Pencil and long strokes under load |
| SwiftUI repeatedly replacing drawings | Stable page identity; update PKCanvasView only for genuine external loads; prevent delegate feedback loops |
| Undo/redo and page switches | Canvas-specific undo scope, flush before switch; test undo after switching pages and returning |
| Missing/corrupt files or full disk | Surface error, preserve bytes, offer recovery; inject missing file, corrupt data and write failure tests |
| Reorder instability | Centralize move/delete normalization to contiguous indices in Phase 2; persisted reopen tests, including duplicate indices |
| PDF alignment, rotation and zoom | One transform for source/canvas/export; test landscape, crop boxes, rotation, multiple page sizes and retina zoom |
| Large PDF memory use | Per-page lazy loading and rendering; cancellable background work, never entire-document rasterization |
| PDF permissions / security-scoped URL | Access only during validated copy, stop scope in defer; reject encrypted/unreadable documents with explanation |
| Export fidelity | Shared page rendering geometry; verify PDF page count, media boxes, rendered orientation, ink and paper; keep source file checksum unchanged |
| SwiftData evolution | Explicit versioned migrations before schema changes, fixture-based migration tests; never delete a failed store |

## Verifiable milestones

1. **Base (implemented):** native Xcode project, iPad split navigation, theme, persistent folder/notebook CRUD, favorite/search, blank page records, metadata overview. Gate: app build, persistence tests, manual rotation/dark-mode/VoiceOver and relaunch checks.
2. **Editor (implemented; see Phase2.md for verification and limits):** PKCanvasView bridge; pen/highlighter/eraser/lasso; color/width; undo/redo; zoom/pan; actual paper rendering; page creation/deletion/duplication/reordering/thumbnails; file actor; debounced saves and flush/recovery. Gate: real Pencil latency checks, interrupted save and disk error tests, order persistence tests and drawing round trips. Page dimensions become explicit, shared with later export.
3. **Documents (implemented; see Phase3.md for limits and validation):** native file picker, immutable PDF copy, page-level ink overlay, independent PDF export service and native iPad share sheet. Export single page or notebook, including templates. Margin extension gets a geometry abstraction; editable extra margins are deferred until explicitly implemented. Gate: geometry fixtures, source immutability, corrupted/encrypted input and large-file memory checks, exported PDF inspection.
4. **Study (requires authorization):** real deck/card CRUD, answer flip with Reduce Motion support, due queue and persistent review history; notebook/page deep links. Start with a pure deterministic interval scheduler using an injected clock and time-zone-aware review dates; document exact Again/Hard/Good/Easy rules and cap/rounding behavior before implementation. Gate: rating/date edge-case tests and history/schedule atomic persistence. Later FSRS fits the scheduling boundary.
5. **Quality (requires authorization):** device profiling, recovery and migration fixtures, accessibility audit, export regression checks, minimum-OS validation and visual polish. Basic error handling and tests remain obligations in every earlier phase.

Out of scope: AI, global handwriting recognition, automatic selection-to-card generation, cloud sync, collaboration, login, audio, subscriptions and other platform apps.

## Apple references

- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [SwiftData introduction and evolution](https://developer.apple.com/videos/play/wwdc2025/291/)
- [NavigationSplitView with SwiftData](https://developer.apple.com/tutorials/develop-in-swift/navigate-sample-data/)

Phase 1 also passed compiler availability checking against the installed SDK with iOS deployment target 17.0. Future PencilKit/PDFKit calls must be checked against that same minimum before use.

## Phase 2 implementation notes

The editor uses an outer UIScrollView to zoom a fixed paper UIView containing a non-scrolling PKCanvasView. Paper and ink therefore share the exact transform. The outer pan accepts direct touch only, leaving Pencil strokes with PencilKit. A custom floating SwiftUI toolbar sets public PKTool values; there is no private API or deprecated finger-drawing property.

EditorSession owns the active page, snapshot revisions, a single in-flight save task and a debounced request. Additional flush callers await the same task. The task repeats if newer ink arrives during I/O; page navigation disables drawing and awaits the final revision. DrawingStorage is an actor using atomic Data writes and checkpoints. A corrupt or missing saved file never becomes a writable empty page automatically. Background save uses UIKit's finite background execution allowance; this is not a guarantee against process termination.

This incremental implementation retains deleted bytes rather than purging them. It has no trash manifest/browser, automatic orphan cleanup or full cross-store filesystem journal. Atomic writes and deterministic UUID paths cover normal saves and interrupted first saves; failed metadata creation/duplication can leave recoverable orphan files. A future storage cleanup feature must account for these limitations and must not remove them silently. The old Phase 1 drawing-file guard has been replaced by real file copying before metadata insertion. Undo history stays in memory and resets across page switches.

Page dimensions are a code-level constant in this phase; landscape paper/custom page sizes are deferred. Thumbnails render ink lazily at low scale; template identity is exposed in the accessibility label rather than rasterized into the thumbnail. All paper templates render on the editor canvas.


## Phase 3 implemented schema

NotePage now stores optional `pdfFilePath`, `pdfPageIndex`, `pageWidth` and `pageHeight`. A PDF source can be shared by multiple pages within a notebook, including page copies. Whole-notebook duplication copies source PDFs into the new notebook directory. V1 is frozen in SchemaVersions.swift and migrates to V2 through a lightweight plan; all binary paths remain relative. The migration fixture includes the actual earlier unversioned store format. The future Study schema above remains a proposal.

## Organization milestone 1

The organization milestone introduced NotesSchemaV3; current metadata is NotesSchemaV4. V2 is frozen separately, with lightweight migrations retaining all document/page IDs and relative paths. Folder now supports optional parent/children, favorite state and trashedAt; Notebook adds trashedAt. Library document/folder removal is recoverable and uses effective ancestor trash visibility. See Organization.md for the actual feature scope, full migration strategy, recovery semantics and deferred Home/Recents/Quick Note, section and Study milestones.

## Current student-tools schema (V4)

V3 is now frozen in SchemaV3.swift. NotesSchemaV4 adds NotebookSection and optional page bookmark/section/object-envelope/right-margin metadata through a tested lightweight V3 → V4 migration. The previous sections describe historical phase decisions; implemented storage, PDF and organization capabilities supersede their early plans. See StudentTools.md for current layering, image lifecycle, section ordering, migration evidence and export semantics. Flashcard models and content search remain unimplemented.
