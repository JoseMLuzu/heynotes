# Contextual toolbar adjustments

The drawing toolbar now uses its spare width for a fixed contextual zone. Primary tool order stays unchanged. The measured intrinsic width of the tool strip determines whether the 276-point quick row fits alongside the palette launcher and separators. Otherwise an ellipsis immediately before the palette opens the same controls in a small popover. Primary tools remain horizontally scrollable in narrow windows. The settings readout reserves the same width across tool changes and integer/decimal values.

## Writing tools and shapes

- Three favorite colors are available for pen, pencil and highlighter. Shapes use the pen's colors, matching their existing shared ink settings.
- Tap a color to apply it without changing width or opacity.
- Touch and hold a swatch, choose Customize Color, use the native picker and Save. Cancel preserves the previous swatch. Editing a favorite does not apply it automatically; tap it to use it.
- Three fixed width shortcuts are shown as fine/medium/thick strokes: pen/shapes 1/3/5 pt, pencil 1/2/4 pt, highlighter 8/18/30 pt. Values are clamped to the installed PencilKit tool's supported range.
- Relative thickness previews use contrasting monochrome marks. Current ink color remains visible in the settings readout; real pressure/tilt behavior still belongs to PencilKit.

Favorites are stored independently per ink family in local ToolPreferences, rather than in a notebook or floating-palette profile. Floating palette favorites/profiles keep their existing independent behavior. Three optional arrays were added to the existing editor.tools.v1 Codable archive; older archives still decode and receive default swatches. Read values are bounded and missing slots use defaults. There is no SwiftData migration or file relocation. Reset This Tool keeps customized quick-color favorites.

## Eraser

The scribble icon selects whole-stroke erasing. The eraser icon selects precise erasing. Three size circles select 10/30/60 pt (bounded to the public native range). Size buttons are disabled in whole-stroke mode and the previous precise size is retained. Mode and size use the existing persisted eraser preferences.

## Inserted objects

Choose Select Objects and select a text box, image, shape or tape rectangle. The contextual buttons edit, duplicate or delete that object. Without an object selection, actions are disabled and a selection hint is shown. The native ink lasso retains its own handwriting actions; it does not pretend to expose inserted-object operations.

Edit opens the real object editor. Saving updates the existing object ID and checks the source page UUID; creating new text still inserts a new ID. Duplication creates independent metadata/UUIDs, offsets the copy where space permits, clamps it to the page, and selects it. Immutable image bytes can be shared by object copies within a page. Deletion requires confirmation and retains image files. Duplicate, edit and delete use the page's existing undo manager and explicit metadata save/rollback path. Page changes retain their existing undo-scope limitations.

## Validation

- 51 native tests pass in the full regression run. Three targeted tests (quick-preference compatibility, actual image-object duplicate/delete/undo, and complete editor rendering) also pass after visual refinements.
- Tests cover independent color persistence, a legacy archive without the new keys, supported width bounds, native precise-erasing width, preserved opacity/width while applying a color, new object IDs, page-edge placement, unchanged image bytes and undo/redo.
- Native captures cover complete editor layouts in landscape light/dark, portrait and a narrow window. A separate component capture covers pen, highlighter, eraser and selected-object controls.
- The signed iOS device build passes with the existing bundle/team and iPadOS 17 target.

Manual acceptance: try colors/widths while taking actual Pencil notes; customize and cancel favorite colors; relaunch offline; switch eraser modes and undo; edit/duplicate/delete a selected object and undo; rotate or resize while the quick controls are displayed; check the compact popover, VoiceOver and larger text. No cloud, AI, flashcard or content-search feature is added here.
