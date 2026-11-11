# Phase 3 — PDF documents

## Implemented behavior

- Library has an Import PDF action using SwiftUI's native file importer. It copies the selected file into the app's private Documents directory with security-scoped access and coordinated reading. Import validates the copied file before inserting metadata. No external account or server is used.
- Imported PDFs become notebooks with one NotePage per source page. Each page stores a relative source path, original PDF page index and normalized visible dimensions. Original bytes are immutable; all PencilKit ink stays in independent `.drawing` files.
- PDF-backed pages use the same Pencil tools, zoom, navigation and page-turn transitions as ordinary notes. Preview loading completes before revealing the new page. An inaccessible or damaged PDF shows a page error rather than a writable blank replacement.
- Add Page creates ordinary note paper with the current page dimensions. PDF page duplication preserves its source reference while copying ink independently. Notebook duplication makes a new private copy of each referenced original PDF and new drawing paths. Reordering/deleting pages affects the notebook's records, not the PDF's original page order or content.
- Editor Page Options includes Export Page as PDF and Export Notebook as PDF. Both await pending ink saves, generate a new temporary PDF and present the native activity sheet (including Save to Files). A progress indicator appears during export. Errors preserve source documents and drawings.
- Paper template changes apply to ordinary note pages; PDF-backed pages retain their source background.

## Architecture and source files

| File | Responsibility |
| --- | --- |
| `Core/Persistence/SchemaVersions.swift` | Frozen Phase 1/2 schema, V2 schema and lightweight migration plan |
| `Core/Models/NotePage.swift` | Optional PDF reference/index and page dimensions |
| `Core/Storage/DrawingStorage.swift` | Validated relative paths, coordinated file copies and binary storage |
| `Features/PDF/Services/PDFDocumentService.swift` | Worker-actor import validation and lazy page preview rendering |
| `Features/PDF/Services/PDFRendering.swift` | Shared crop/rotation transform and paper renderer |
| `Features/PDF/Services/PDFExportService.swift` | Independent PDFExporting service; page-at-a-time PDF composition |
| `Features/PDF/Services/LibraryPDFImport.swift` | Import metadata transaction and visible errors |
| `Core/Components/PDFShareSheet.swift` | Native activity sheet integration |
| `Features/Editor/Services/EditorSession.swift` | Safe page loading, PDF preview, export snapshots and save-before-export |
| `Features/Editor/Components/PaperCanvas.swift` | Dynamic-size canvas and PDF background under editable ink |
| `Features/Editor/Components/PageThumbnail.swift` | Lazy PDF/ink thumbnail layers |
| `NotesAppDeviceTests/PDFDocumentTests.swift` | Actual PDFKit/PencilKit import, rendering and export tests |
| `NotesAppTests/MigrationTests.swift` | Reopening a previously unversioned Phase 2 store with V2 |

The Xcode source registration script now explicitly locates each target's source phase rather than depending on PBX dictionary ordering. Signing configuration and schemes are preserved.

## Coordinates, fidelity and performance

PDFKit opens and validates the copied PDF. Core Graphics uses the source page's crop box and rotation to produce a normalized, top-left page space. A 90°/270° page swaps width and height. Preview and export use the same transform; ink is drawn in that normalized coordinate space. Existing visible PDF annotations are drawn after the PDF page contents.

The editor renders one PDF background at a time off MainActor, at up to 2400 pixels on its longest edge (scale capped at 2×). This is a bounded raster preview, so fine PDF text can look softer at high zoom; dynamic vector tiling and text selection are future improvements. Thumbnails are limited to 240 pixels. The original PDF remains intact and is used directly during export, preserving its vector/text content rather than exporting the preview image.

Export writes pages to a file using UIGraphicsPDFRenderer, releases each temporary page raster in an autorelease pool, and reuses the current source PDFDocument between adjacent source pages. PencilKit's public drawing image API rasterizes the ink layer at up to 2× page resolution, capped at 4096 pixels on its longest edge. Exported ink is flattened; editable ink stays in the app's drawing files. Source PDF text is preserved in the tests. This is not a claim that all PDF features survive flattening: hyperlinks, forms, signatures, tags and bookmarks are not copied as interactive structures.

Export PDFs use the normalized visible crop size and orientation, rather than reproducing an offset crop box or retaining a `/Rotate` entry. No source PDF file is rewritten by import, annotation or export. Pages with nonfinite, zero or greater-than-14400-point dimensions are rejected to avoid invalid Core Graphics allocations. Extremely large or malformed PDFs are not exhaustively supported.

Worker actors confine PDFKit objects; only immutable descriptors, URLs and rendered images cross to the main actor. SwiftData objects stay on MainActor. No whole-notebook raster or whole-source Data read is needed during production import/export.

## Migration and recovery

The original unversioned schema is frozen as NotesSchemaV1. NotesSchemaV2 adds only optional PDF fields. The migration plan uses a lightweight migration; old pages default to 768 × 1086 points with no PDF source. A test creates a real unversioned store with folder, favorite and drawing references, then migrates and verifies them.

Migration failure never deletes or recreates the user store. Existing relative ink paths remain unchanged. App updates keep the existing bundle identifier and default SwiftData store location.

The existing retention policy still applies: deletion retains private source PDFs, drawings and backups. There is no trash/recovery browser or automatic orphan purge. Invalid imports or failed metadata transactions can leave unlinked private PDF copies; these are retained for recovery, never silently removed as user data. Failed exports remove only their own unique temporary directory. Successful exports live in the OS temporary directory and may eventually be reclaimed by the system.

## Manual acceptance

1. Open existing handwritten notebooks after the update. Verify titles, folders, favorites, page order, templates and strokes.
2. Import a PDF from On My iPad and from a file provider. Put it in a folder, relaunch offline and annotate it. The original external file must remain unchanged.
3. Import portrait, landscape, mixed-size, cropped and rotated PDF pages. Write near all four corners, zoom/pan, turn pages and confirm alignment. Check thumbnails and page transitions.
4. Switch pages immediately after writing, background the app, reopen and confirm ink persists. Duplicate a PDF page and a whole PDF notebook; edit only the copies and confirm independence.
5. Export the current PDF page, a whole PDF notebook and an ordinary handwritten notebook. Use Save to Files and inspect all pages in Files/Preview, including size, rotation, background and ink placement.
6. Try corrupt, empty, locked/password-protected and printing-restricted PDFs. They must show an error without a new notebook record. Missing private PDF files must not become editable blank pages.
7. Test a large lecture document for memory use and responsiveness. Export remains a worker operation; this phase does not provide a cancel button or per-page progress percentage.
8. Check portrait/landscape, dark mode, large text, VoiceOver, native share-sheet presentation and real Apple Pencil behavior on the physical iPad.

## Explicitly deferred

Update: right-side note margins are now implemented in the student-tools delivery, including page controls, source-preserving geometry and normal/practice PDF export. See StudentTools.md for scope, migration and regression coverage.

PDF text selection/search, password-entry UI, editable PDF-native annotations, vector ink export, interactive form preservation and a document recovery browser remain future work. Flashcards are Phase 4 and are not implemented here.

## Apple API references

- [PDFPage bounds and page coordinates](https://developer.apple.com/documentation/pdfkit/pdfpage/bounds(for:))
- [UIGraphicsPDFRenderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer)

All new code compiles against the installed SDK with deployment target iPadOS 17.0. It does not require iPadOS 27-only APIs.


## Executed validation

- PASS: 10 host tests across persistence, storage, ordering, duplication and migration, including reopening an unversioned Phase 2 store.
- PASS: 9 native tests on an iPad Air 11-inch simulator (5 editor tests and 4 document tests).
- PDF fixtures cover portrait/landscape pages, mixed sizes, nonzero crop origins, a 90-degree rotation, blue ink overlay, grid paper, text retention, locked/corrupt input and missing drawing files.
- Pixel assertions verify rotated and cropped source placement and exported ink placement. Source and private-copy bytes match after import/export. Notebook-copy tests verify distinct source paths and page editing/export from the editor service.
- Physical iPad review of the file picker, share sheet, Pencil input and preview quality remains necessary.

Delivery: the signed generic iOS device build passed with the existing team and bundle identifier. The connected-device query reported the user's iPad Air as unavailable, so Phase 3 has not been installed on that device by this session. Reconnect/unlock the iPad and run the NotesApp scheme with ⌘R. No existing app or device data was removed.
