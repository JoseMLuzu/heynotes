# HeyNotes — Write. Study. Remember.

A native, offline-first iPad notes app. **Phases 1, 2 and 3 are implemented.** There are no accounts, analytics, networking services, dependencies, payments, or cloud entitlements.

## Student tools

Study tape, native ruler/vector shapes, named page bookmarks, notebook sections, extended PDF note margins, typed text and image insertion are implemented. All editor controls remain at the top. See [StudentTools.md](Documentation/StudentTools.md) for usage, V4 migration, export behavior, tests and incremental limits. Flashcards and handwriting/content search remain deferred.

## Requirements and verified environment

- Deployment target: **iPadOS 17.0**, iPad only; portrait, landscape, and resizable iPad windows.
- Language mode: **Swift 6**, complete strict concurrency checking.
- Inspected environment: Xcode **27.2 (27B52)**, Swift compiler **6.4.2**, iOS / Simulator SDK **27.2**.
- No iPadOS 27-only API is intentionally used. SDK availability checks compile against the 17.0 target. Runtime behavior on iPadOS 17 still needs a compatible device or runtime.

## Run in Xcode

1. Open `NotesApp.xcodeproj` (not `Package.swift`). The native app project and shared `NotesApp` scheme are already included.
2. Select the **NotesApp** scheme and an iPad simulator. Install an iOS simulator runtime in Xcode Settings if needed.
3. Press **⌘R**.
4. For a physical iPad, select your development team in Signing & Capabilities, use a unique bundle identifier, enable Developer Mode on the iPad, and run.

The repository was initially empty. To recreate the shell manually: File → New → Project → iOS App, product name NotesApp, interface SwiftUI, language Swift, no initial storage template. Choose iPad only, iOS 17.0, and Swift 6; replace the generated app with these source files. Using the included project avoids this work.

The standard-library-only helper `python3 Scripts/generate_project.py` registers new Swift sources under `NotesApp/` in the existing project. It preserves signing settings, targets, and the shared scheme. No project generation tool is needed to open or build the checked-in project.

## Phase 1 behavior

- Native split navigation: Library, Favorites, Study, and folders/subjects.
- Adaptive notebook grid, title search, modification date, page count, and color covers.
- Create notebooks with a first page and blank, ruled, or grid template metadata.
- Create, rename, and delete folders. Deleting a folder keeps its notebooks.
- Notebook context menus: rename, favorite, move, duplicate, and confirmed deletion.
- Independent UUIDs for duplicated notebooks and pages; deterministic page ordering.
- Local SwiftData storage with explicit saves, rollback, visible errors, and no destructive store reset.
- System light/dark surfaces, Dynamic Type, SF Symbols, and accessible notebook labels.
- Opening a notebook launches the real PencilKit editor described below.

Study explains its scheduled phase. PDF import and export are implemented; flashcards remain in Phase 4. The app does not insert sample content.

## Source map

| Location | Responsibility |
| --- | --- |
| `NotesApp/App/` | Entry point, dependency composition, recoverable startup error screen |
| `NotesApp/Core/Models/` | Folder, Notebook, NotePage, NotebookSection, inserted objects, cover and paper values |
| `NotesApp/Core/Persistence/` | Explicit local SwiftData container, test configurations |
| `NotesApp/Core/Theme/` | Semantic surfaces and notebook palette |
| `NotesApp/Features/Library/ViewModels/` | Validated metadata mutations, saves and rollback |
| `NotesApp/Features/Library/Views/` | Sidebar, grid, forms and cards |
| `NotesApp/Features/Editor/` | PencilKit bridge, tools, save coordination and page management |
| `NotesAppTests/` | Host-side Swift Testing tests against the production metadata code |
| `Documentation/Architecture.md` | Relationships, storage design, risks and phase gates |
| `Documentation/Validation.md` | Automated results, environment limitations and manual checklist |

Future feature directories are added when they have real implementations. See the architecture document for their responsibilities.

## Automated checks

```sh
xcodebuild -project NotesApp.xcodeproj -scheme NotesApp \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/notesapp-derived CODE_SIGNING_ALLOWED=NO build

swift test
```

The Swift package is a **macOS host test harness for metadata only**, not a Mac version of the app. It compiles the same model, persistence and view model sources and runs without an iPad simulator. Open `Package.swift` separately in Xcode to use its test UI. The native NotesApp scheme additionally includes NotesAppDeviceTests (PencilKit, save flushing and recovery); run those with ⌘U and an iPad simulator.

Continue with Phase 4 only after an explicit request.

## Phase 2 — Handwriting

Open any notebook. The editor provides pen, highlighter, vector eraser, lasso, ink color, configurable widths, undo/redo, and a floating tool strip. Apple Pencil draws by default. At full-page zoom, short horizontal finger flicks turn existing pages; on the last page, pull left and hold for **0.5 seconds** to create a page. A progress indicator shows the countdown, and lifting early cancels it. When zoomed in, one finger pans; two fingers pinch to zoom. Enable **Draw with Finger** in Page Options for touch testing; pan with two fingers in that mode. Paper stays white in dark mode so saved ink has a consistent appearance. See [page gesture behavior and validation](Documentation/PageGestures.md).

Use **+** in the top editor header to add a page. Tap the adjacent page counter/grid icon to open thumbnails and Previous/Next controls on demand; finger swipes also turn pages. The editor has no bottom page bar. Narrow windows place tools on a second row at the top. Page Options supports paper templates, page duplication, moving earlier/later, and confirmed deletion. At least one page is kept. Undo/redo is scoped to the open page's current canvas session; page switches reset its history. Sidebar navigation and the Library button save before leaving the editor.

Each page uses 768 × 1086 logical points (portrait paper); this stable coordinate system is ready for Phase 3 export. Ink uses editable PKDrawing data, never a flattened image. Serialization and file access run away from the main actor. Saves debounce at 650 ms, serialize outstanding snapshots, and explicitly flush before page navigation and leaving. App backgrounding requests additional execution time to flush. Tapping the save status retries a failed save. Force termination can still lose ink created since the most recent checkpoint.

Files live at `Documents/Notebooks/<UUID>/Pages/<UUID>.drawing`. Paths in SwiftData remain relative. Atomic replacement keeps the previous checkpoint as `.backup`. Missing/corrupt ink opens an error view instead of an editable empty canvas; Retry and Restore Backup are available. Recovery preserves damaged bytes separately. New-page files written just before an interrupted metadata save are discoverable through their deterministic UUID path on reopening.

Deleted page/notebook drawing files are deliberately retained, including backups, so deletion never silently purges handwritten bytes. Recovery of deleted pages currently requires manual file recovery; there is no deleted-item browser or automatic storage cleanup yet. Failed duplications may similarly retain unlinked copies. Do not interpret this as a complete trash system.

Key new source files: `Core/Storage/DrawingStorage.swift`, `Core/Models/PageOrdering.swift`, `Features/Editor/Services/EditorSession.swift`, `Features/Editor/Components/PaperCanvas.swift`, `Features/Editor/Components/PageThumbnail.swift`, and `Features/Editor/Views/EditorView.swift`. The library view/model now open the editor and copy saved drawings independently when duplicating notebooks. Phase 2 did not change the schema; Phase 3 adds optional PDF fields through a tested migration.

See [Phase 2 validation](Documentation/Phase2.md) for tests, remaining limits, and real-iPad acceptance checks.


## Phase 3 — PDF documents

Use **Import PDF** in Library to create an annotated PDF notebook. Open it and use the same Pencil tools and page controls as handwritten notes. **Page Options → Export Page as PDF / Export Notebook as PDF** generates a new PDF and opens the native share sheet. Save to Files to retain your export. The source document is never rewritten.

PDF pages preserve their visible size/orientation, have independent editable ink layers and can be mixed with added note pages. The editor uses a bounded background preview; export draws original PDF content plus flattened ink. Extended margins, PDF text selection, password entry and interactive form preservation are deferred.

See [Phase 3 architecture, limits and acceptance checklist](Documentation/Phase3.md). A frozen V1 schema and lightweight V2 migration preserve existing notebook metadata and ink references. Device PDF tests are part of the NotesApp scheme (⌘U); host persistence/migration tests run with `swift test`.

## Visual refinement

The library uses porcelain-white surfaces, soft blue accents and lighter book-like covers. Notebook creation previews the cover as you choose its color. The compact editor keeps its single-row layout with a quieter selected-tool treatment. See [design direction and review checklist](Documentation/Design.md).

## Tool options

Tap the selected tool again or use its controls button for additional settings. Pen, pencil and highlighter have independent widths, opacity, a 12-color palette and custom colors. Eraser supports whole strokes, precise partial erasing with size control, and confirmed/undoable clearing of page handwriting. Settings persist locally. See [tool behavior and validation](Documentation/Tools.md).

## Quick Palette

Use the floating box to switch between up to six saved tool configurations. Drag its grip with one finger, tap **−** to collapse, **…** to customize/reorder, or **+** to save the current tool. Long-press a favorite to edit or replace it. Favorites and viewport-relative position persist; the palette stays on-screen after rotation. The permanent **paint palette icon in the editor header** restores it when hidden/collapsed and hides it when expanded. Long-press that icon to restore its default position. **Page Options → Quick Palette** is also available. See [palette behavior and validation](Documentation/QuickPalette.md).

The profile-name selector inside the palette switches between independent favorite sets. **Manage Profiles** lets you create a profile from the current tool, duplicate one, rename it or confirm deletion. Existing favorites migrate into **My Palette**; the last selected profile persists. Switching profiles leaves the current writing tool unchanged until you select a favorite.

## Performance

PDF previews and page thumbnails now use bounded, source-aware caches; gallery rendering has its own worker queue, thumbnails have fixed pixel limits, and autosave avoids repeated checkpoint writes while preserving explicit flush guarantees. See [performance measurements, verification and hardware limits](Documentation/Performance.md).

## Document tabs

Open several notebooks from Library and switch between their tabs above the editor. Library/+ lets you open another document; × closes only its tab. Recently Opened restores closed/recent notebooks. Tabs and last visited pages are remembered across launches, and switching waits for pending ink saves. Only the active notebook keeps a live editor to limit memory use. See [workspace behavior and verification](Documentation/Workspace.md).

## Organization — first milestone

Folders now support nested subfolders, full-path moves, folder favorites and recoverable Trash. Inbox shows unfiled notebooks without duplicating files. Trash preserves folder/document/page relationships and binary files; restore returns items to their original locations. The V3 schema has tested migrations from the earlier stores. Home/All Notes/dated Recents/Quick Note, notebook sections and real Study remain later milestones. See [organization plan and recovery semantics](Documentation/Organization.md).

## Templates

Open **Templates** in the Library sidebar to browse 16 backgrounds across Notes & Paper, Study, Planner & Calendar and Productivity. Search or select a category, then use the template in a new notebook. The notebook form also offers **Browse Templates**; existing note pages use **Page Options → Page Template**. Changing paper preserves handwriting, and new pages inherit it. Layouts render consistently in previews, the editor and exported PDFs. Planners are undated writing guides; Flashcard Sheet is paper rather than a Study deck. See [template scope, storage and validation](Documentation/Templates.md).

## Notebook covers

Use **New Notebook → Browse Covers** or a notebook's context menu → **Change Cover**. The gallery includes the 40 supplied designs in Linen, Waves, Patterns, Botanical and Textures, plus the five original colors. Covers remain offline, persist through reopening/duplication, and leave pages and PDF originals unchanged. See [cover collections, compatibility and verification](Documentation/Covers.md).
