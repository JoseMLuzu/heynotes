# Organization system — inspection, migration and phased delivery

## Existing implementation inspected

The app already has feature-based lightweight MVVM, native SwiftUI split navigation, a document-tab workspace with a single active editor, PencilKit drawing, page UUIDs and stable pageIndex ordering, atomic per-page files, PDF import/annotation/export and bounded preview caches. SwiftData stores Folder, Notebook and NotePage metadata. File paths remain relative to the app's private Documents root.

Before this milestone, Folder was flat; Favorites applied only to notebooks; deleted notebook metadata was permanently removed while binary files were retained. Document-tab history lived in UserDefaults. There is **no StudyDeck, Flashcard or ReviewRecord model yet**. Study is an explicit coming-soon screen, not a working review system. No study counters are fabricated.

## Delivery milestones

1. **Hierarchy and recovery — implemented here.** Nested folders, inline sidebar expansion, subfolder cards, context actions, cycle-safe folder movement, folder favorites, virtual Inbox, recoverable notebook/PDF/folder trash and safe workspace integration.
2. **Fast library navigation — partially implemented.** Name, Recent and Type sorting are available in the library grid. Remaining work includes Home, All Notes, persistent lastOpenedAt distinct from updatedAt, a dedicated Recents view, global New Quick Note, and grid/list modes. First-page PDF previews are now available in document cards. Quick Note will create a normal one-page notebook in virtual Inbox and open it after successful saving; no orphan NotePage is needed.
3. **Notebook sections — implemented in the student-tools delivery.** NotebookSection has stable UUID/order and optional NotePage.section. The page index creates, renames, reorders and removes sections while preserving their pages; thumbnail menus move pages. Named bookmarks filter the same index. Page IDs and drawing paths survive regrouping. See StudentTools.md for V4 migration and validation; page metadata deletion still has the existing retained-binary recovery limitation.
4. **Study integration — deferred.** Real StudyDeck/Flashcard/ReviewRecord models, review scheduling, due counts and permanent source links. Decks may reference a notebook. Cards may retain optional notebook and page references; moving a page between sections must not alter its UUID. Deleted/trashed sources need restore/unavailable guidance instead of a broken navigation path. Existing notebook duplication must not implicitly duplicate decks without a defined user action.

The later milestones are design plans, not empty placeholder implementations. This delivery deliberately does not claim the full requested sidebar or Study workflow is finished.

## Implemented hierarchy behavior

- A folder has an optional parent and inverse children relationship. Sidebar OutlineGroup expands/collapses live subfolders. Opening a folder shows its immediate subfolders, notebooks and PDF notebooks.
- Library shows root folders and unfiled documents. A title search in Library can find nested folders/documents. Inbox is a virtual view of notebooks whose folder is nil, not another stored Folder or a copied document.
- New Folder in the sidebar creates a root folder. The folder context menu and toolbar within a folder create subfolders in that location.
- Folder context menus support rename, new subfolder, favorite, move and Move to Trash. Movement choices show full paths; service validation also walks destination ancestry to reject self/descendant cycles even if called outside the UI.
- Notebook/PDF moves only change folder metadata. Page/notebook UUIDs, drawing paths, source PDF paths and binary bytes are not copied or rewritten by moves.
- Favorites is virtual and combines live favorite folders with favorite notebooks/PDFs, retaining each original location. Trashed descendants do not appear in Favorites.

## Trash semantics

Notebook/PDF removal sets Notebook.trashedAt. Folder removal sets Folder.trashedAt on the selected folder and makes all descendants effectively trashed through ancestry. No metadata relationship is disconnected; no page, drawing, PDF or backup is removed. The confirmation states the live subfolder/document counts being affected.

Trash displays top-level removed folders and explicitly removed notebooks whose containing folder is not itself trashed. Restoring a folder makes its previously live descendants visible again at their original locations. Items independently trashed before the folder stay trashed and become separately restorable after the parent is restored. Restoring an item beneath a still-trashed parent is rejected with guidance to restore the containing folder first.

There is no permanent-delete or Empty Trash action in this milestone. Retained data consumes storage; safe purge/retention policies are future work. Metadata permanently removed by older builds cannot be reconstructed automatically just from their leftover binary files; this feature protects removals made from this version onward.

Before moving a folder to Trash, the workspace flushes its active affected notebook once and removes all affected tab/history references without loading each intermediate document. If saving fails, removal does not proceed. Restoring workspace tabs filters effectively trashed documents and opening a trashed notebook is rejected until restored. Restoring a notebook does not automatically reopen its old tab.

## Safe migration

NotesSchemaV1 remains frozen. The exact previously shipped V2 layout is now frozen in `Core/Persistence/SchemaV2.swift`; V2 no longer aliases mutable current model classes. That milestone used NotesSchemaV3; its exact layout is now frozen in SchemaV3.swift. Current models form NotesSchemaV4 (see StudentTools.md).

V3 adds:

| Model | New persisted properties | Existing-data default |
| --- | --- | --- |
| Folder | parent, children | nil / empty; existing folders remain root folders |
| Folder | isFavorite | false |
| Folder | trashedAt | nil; existing folders stay live |
| Notebook | trashedAt | nil; existing notebooks stay live |

The migration plan contains lightweight V1 → V2 and V2 → V3 stages. There is no destructive store fallback. Existing folder/notebook/page UUIDs, page order, templates, favorites, drawing paths, PDF source references and dimensions remain unchanged. No binary storage migration runs.

The student-tools delivery adds sections/bookmarks/content/margins through a tested V3 → V4 migration. lastOpenedAt and Study models remain deferred. Each later schema change must preserve the current version and add a tested migration stage.

## Source files

- `Core/Models/Folder.swift`, `Notebook.swift`: hierarchy/favorite/trash metadata.
- `Core/Models/FolderHierarchy.swift`: cycle-bounded ancestry, subtree IDs, visible children and full paths.
- `Core/Persistence/SchemaV2.swift`, `SchemaVersions.swift`, `PersistenceController.swift`: frozen snapshots and V3 migration.
- `Features/Library/ViewModels/LibraryViewModel.swift`: soft removal/restoration, folder movement and destination checks.
- `Features/Library/Views/FolderActionsMenu.swift`, `LibraryTrashView.swift`: native folder actions/cards and recovery UI.
- `Features/Library/Views/LibraryView.swift`, `NotebookForm.swift`: nested navigation, virtual Inbox, full-path locations and clear confirmations.
- `Features/Workspace/ViewModels/DocumentWorkspace.swift`: batch removal of tab references after saving and exclusion of trashed documents.

The existing PencilKit canvas, PDF renderer, drawing format and export geometry are preserved.

## Verification

- PASS: 17 host tests. They include real store migration from unversioned V1 and versioned V2 to V3, PDF path/dimension and UUID preservation, inverse folder relationships, cycle rejection, metadata-only document moves, nested trash/restore semantics and reopening an on-disk V3 hierarchy.
- PASS: all 24 native tests. New cases also reject PDF imports into trashed folders and cover saving/closing a folder's affected tabs before trash, preserving ink bytes through restore, and rejecting removal when the active drawing cannot be saved. Existing editor, PDF, performance, tool and tab tests still pass.
- PASS: generic simulator app build.

Manual acceptance on iPad: migrate/open existing notebooks, create a three-level hierarchy, move documents and folders, reject a cycle through service/UI destinations, favorite folders, inspect Inbox, trash a folder with multiple open documents, restore it and verify page order/ink/PDFs. Repeat in portrait/landscape, dark mode, large Dynamic Type and VoiceOver. Confirm no file copies occur when moving items and no permanent-delete action is offered.

The final simulator suite passed on iPad Pro 13-inch after an earlier iPad Air run was rejected as Busy before test execution. The signed generic iOS device build passed.

Device delivery: this milestone installed successfully over the existing Notes app on the connected iPad Air, using the same bundle identifier and metadata store location. The build also includes the document tabs whose earlier installation was blocked by device locking. Physical UI, migration of the user's own library and Pencil acceptance still require review on the device; automated migration fixtures passed before delivery.

Launch status: CoreDevice rejected automatic opening because the iPad screen was locked (FBSOpenApplicationErrorDomain code 7). Installation succeeded, but the user must unlock the iPad and open Notes to run the new build and its on-device store migration. No unlock/security bypass was attempted.

## Library presentation update — 2026-11-09

Folder cards now use the same portrait dimensions and adaptive grid columns as notebooks. Both share LibraryItemCaption, reserving two lines below each cover and keeping row tops aligned for long titles. Folders retain navigation, favorite badges and existing move/rename/trash context actions; no data migration is required.


## Library sorting — 2026-11-11

Use the arrow-up/arrow-down menu above the document grid to choose Name, Recent or Type. Folders appear first. Name uses localized natural order, including numbered titles such as Lecture 2 before Lecture 10. Recent orders notebooks by updatedAt, newest first. Folder activity uses its creation date, descendant folder creation dates and contained notebook modification dates. Type groups handwritten notebooks before documents containing PDF pages, with alphabetical order within each group. Equal names/dates have stable UUID tie breaks.

The choice persists in the local library.sortOrder preference and applies to Library, folders, Inbox, Favorites and matching search results. Recent is the initial default. This is a display-order preference, with metadata and binary files retaining their existing values. The sidebar keeps its alphabetical folder hierarchy.
