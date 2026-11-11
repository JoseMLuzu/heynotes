# Paper template gallery

## Scope and use

The native gallery takes its visual direction from the supplied pastel template reference: a category sidebar, grouped horizontal shelves, larger category grids, readable previews, restrained sage/lavender/rose accents, and explicit selection. Search matches template titles and descriptions. The interface uses system surfaces and SF Symbols; the writing paper stays white to preserve ink appearance in either color scheme.

- **Library → Templates** opens the gallery. Choose **Use Template** to continue to the notebook form; title, cover and destination remain editable before creation.
- **New Notebook → Paper → Browse Templates** selects the first page's background.
- **Editor → Page Options → Page Template** changes the current note page. Existing strokes and page IDs remain intact. PDF source pages keep their original backgrounds; added note pages can use templates.
- New pages inherit the current paper template. Cancel never applies a selection.

The initial catalog contains 16 usable backgrounds:

| Category | Templates |
| --- | --- |
| Notes & Paper | Blank, Ruled, Grid, Dotted, Isometric, Music Staff |
| Study | Cornell Notes, Lecture Notes, Flashcard Sheet, Study Plan |
| Planner & Calendar | Daily Planner, Weekly Planner, Undated Calendar |
| Productivity | To-Do List, Kanban Board, Habit Tracker |

These are handwriting layouts. Planners are undated, habit trackers have 31 blank day columns, and checkboxes are drawn guides. The Flashcard Sheet does not create a Study deck or implement spaced repetition. Annual planners, finance, wellness, custom template import and interactive calendar data are outside this increment; no empty categories or simulated data are displayed.

## Rendering and persistence

`PaperTemplate` remains a raw-string enum stored through the existing `NotePage.paperTemplateRawValue`. The legacy `blank`, `ruled` and `grid` identifiers and spacing remain unchanged. This catalog expansion adds no SwiftData properties or schema migration. Existing UUIDs, drawing paths and immutable PDF originals remain unchanged.

`TemplateRenderer` draws with Core Graphics and Core Text. Gallery previews, editor paper, page thumbnails and PDF export share the same renderer through `PDFRendering.paper`. Export keeps template lines/text as vector content and overlays the existing ink in page coordinates. Selecting the already active template does not update modification dates.

Structured layouts use a 768-point design width, adapt to normal portrait/landscape note dimensions, and constrain drawing to page bounds. Repeated guides are bounded; very narrow, wide or tall PDF-derived note sizes can have additional whitespace. Validate unusual aspect ratios before extending the catalog to custom page sizes. Standard note pages use 768 × 1086 points.

## Verification

- 19 host tests passed, including legacy template IDs and reopening a persisted template change while preserving page identity and drawing references.
- 27 native simulator tests passed, including all 16 PDF backgrounds, PDF page dimensions and searchable headings, real PencilKit ink coordinates over a structured layout, unchanged source drawing bytes, inherited templates and PDF-background protection.
- Exported Cornell, daily and weekly preview attachments were reviewed for layout, text orientation and subtle guide contrast.
- The native simulator UI was reviewed: Library entry, grouped shelves, Study category grid, selected-card feedback, confirmation into the notebook form with Cornell retained, and cancellation without creating a notebook.
- The signed device build succeeded and was installed and launched on the connected iPad Air (5th generation). Installation does not establish Apple Pencil acceptance or persistence across force termination.

Manual iPad acceptance: browse all categories and search; cancel and confirm from each entry point; write on a Cornell page then switch to weekly paper; add a page; reopen the notebook; export both pages and inspect ink alignment. Check split-screen, portrait/landscape, Dynamic Type and VoiceOver selection announcements. Physical Apple Pencil responsiveness and gallery touch interactions on hardware still require device review.
