# Notebook cover collections

## Behavior

The 40 covers in the supplied **Pastel Notebook Cover Gallery.png** remain available offline in Linen, Waves, Patterns, Botanical and Textures. Originals retains Sage, Blue, Sand, Rose and Graphite. The new Subjects collection adds 12 native vector designs, for 57 choices total. New notebooks still default to the original Sage cover.

- **New Notebook → Browse Covers** opens the full-screen gallery, with collection filters, search, selection feedback and an explicit **Use Cover** action. The creation preview updates immediately; the notebook is saved only after Create.
- Touch and hold an existing notebook/PDF notebook in Library and choose **Change Cover**. Confirmation persists the choice with normal metadata save/error handling. Cancel leaves the notebook unchanged; a failed save keeps the picker open and displays the error.
- Copies retain the selected cover. Moving, favoriting, trashing and restoring retain its identifier. Small accent cues remain consistent in tabs and the editor header.
- The supplied atlas artwork has no imposed initial/text, matching the reference. Subject covers have printed subject names and short decorative subtitles; the user document title remains below the cover. PDF/favorite badges are overlaid where applicable.

Covers are library decoration; they do not replace paper templates, insert a new page, modify handwriting or change PDF export contents.

## Persistence and compatibility

`CoverStyle` defines stable raw identifiers. The five original raw strings remain unchanged. The existing `Notebook.coverColorRawValue` string column stores either an original color ID or a namespaced artwork ID, such as `botanical.olive`. The new `coverStyle` accessor resolves artwork; `coverColor` remains a five-color accent accessor for existing UI consumers. No persistent field, schema version, UUID or binary path changed, so no SwiftData migration is needed.

Unknown identifiers render with the existing Sage fallback while retaining the stored raw string. Choosing an already active cover does not change the edit date. Duplication copies the raw identifier, including unrecognized values, rather than flattening it to an accent color. Future catalog updates must preserve these identifiers and artwork mappings; do not reorder enum cases without updating the explicit atlas index contract.

## Artwork and packaging

The supplied 1536 × 1024 PNG is bundled unchanged in `Resources/Assets.xcassets/NotebookCoverAtlas.imageset`. No generated substitute was used. `CoverArtwork` displays the 40 tiles using fixed source coordinates that exclude gutters. The app clips each tile to the native cover shape and applies its normal shadow. The resource stays in the app bundle, not in each notebook's document folder. At most 40 small tile images plus one atlas are retained; drawing/PDF caches are independent.

The source is a gallery-resolution image: individual tiles are approximately 152–158 pixels wide. It is suitable for this initial library integration, but larger individual originals should replace the atlas before presenting large zoomable covers. Preserve identifiers when upgrading artwork. Confirm rights to distribute the supplied designs before App Store publication.

`Scripts/generate_project.py` now registers the asset catalog in the app's resources phase while continuing to preserve signing, targets and source membership. The host Swift package excludes the UIKit/SwiftUI cover feature.

## Verification

- 20 host tests passed, including actual-store reopening after a cover change, independent duplication of saved ink, PDF/page metadata preservation, same-cover date behavior, Trash protection and existing V1/V2 migrations.
- 28 native simulator tests passed. The added resource test resolves all 40 bundled tiles, verifies unique artwork and produces a contact sheet through the production SwiftUI cover view. The contact sheet was visually reviewed for tile alignment, clipped gutters, colors and native card treatment.
- Simulator and signed iOS builds passed. Full-size Pencil/device interaction and VoiceOver/Dynamic Type gallery acceptance remain manual checks.
- Native simulator UI review confirmed the creation-form entry, collection filtering, artwork previews and Tulips selection feedback. Confirmation/back-navigation and changes on a physical library remain manual acceptance checks.

The final visual pass reduced the minimum preview width so eight-cover collections fit more naturally on iPad, and initializes the creation folder once rather than resetting it on reappearance after a picker. These presentation-only changes compiled in the signed device build after the 48-test run.

Delivery: the first device installation lost its connection. A later retry succeeded, and the final build including the folder-selection fix was also installed successfully over the existing Notes app on the connected iPad Air (5th generation). No document reset or file relocation was performed.

Manual acceptance: choose and cancel covers during creation; change an existing notebook's cover, reopen it and verify ink; duplicate/move/trash/restore it; test PDF badges, search/filtering and narrow/landscape layouts. Cover changes must not introduce pages or alter source PDF files.

## Subjects collection — 2026-11-09

Twelve new designs cover Mathematics, Science, History, Biology, Chemistry, Physics, Literature, Geography, Computer Science, Economics, Languages and Art. They appear first under Subjects in All Covers and have their own filter. Gallery search accepts English titles and Spanish subject keywords, including accented and unaccented forms. Creation and Change Cover use the same real gallery/save workflow.

SubjectNotebookCover and SubjectCoverIllustration draw pastel stationery, a quiet spine, serif subject headings and distinct scalable line illustrations with SwiftUI/Canvas. These are native vector designs, requiring no generated images, fonts, network, per-notebook artwork files or bitmap-cache expansion. Their printed colors stay consistent in light/dark mode, like physical covers. PDF/favorite badge spacing is reserved and badge sizes scale with subject-cover previews. The diagrams are decorative illustrations, not scientific reference material or interactive graphs.

Stable subjects.* IDs are appended after the 45 existing styles in CoverStyle and stored in the same coverColorRawValue string field. NotebookSubject supplies titles, search terms and the existing five-color tab accent family. No SwiftData property/schema changes, page insertions, drawing writes or source-PDF edits occur. The first 40 atlas indices remain fixed at 0...39; subject covers return no atlas index, and image lookup also validates bounds. Copies preserve subject IDs and keep independent document/page metadata.

Validation: 23 host tests and 51 native tests pass. A real-store fixture changes a saved-ink notebook to a subject cover, duplicates it, reopens it and verifies the subject identifier, page identity, unchanged bytes and original atlas boundaries. The native resource test still validates all 40 distinct supplied tiles, and renders a 12-cover contact sheet through the production cover view, including PDF/favorite badges. The contact sheet was visually inspected. The signed iOS build passes against the iPadOS 17 deployment target.

Manual acceptance: New Notebook → Browse Covers → Subjects; select a subject and create the notebook. On an existing notebook or PDF, touch and hold → Change Cover → Subjects → Use Cover. Try searching matematicas, ciencias, historia and quimica. Reopen, duplicate and check existing ink; inspect light/dark mode and smaller gallery tiles.
