# Handwriting Style

## Scope and availability

Opt-in handwriting-to-text conversion runs entirely on the iPad. It uses PencilKit source strokes, Vision text recognition and Core Text font layout. It does not train a personal handwriting model or create a font from a photo/sample. The original PencilKit editor remains the default, and conversion starts off in each editor session. Font, language and alignment preferences persist locally.

The deployment target remains iPadOS 17 with the installed Xcode 27.2 SDK. The implementation uses `VNRecognizeTextRequest` and process-scoped `CTFontManagerRegisterFontsForURL`; it does not require iPadOS 27 stroke recognition or system-wide font installation. There are no account, server, remote model or font-download dependencies.

## Workflow

1. Open Insert → **Handwriting Style**. Select a font and English/Spanish recognition.
2. Optionally choose **Import Your Font…** and select a single-face `.ttf` or `.otf` file in Files. A font previously created from your handwriting works through the same import. Font creation/training is separate and is not implemented here.
3. Adjust **Align to Paper Lines**, **Letter Size** (70–130%) and **Baseline Adjustment** (−8 to +8 logical page points). Negative adjustment moves converted text upward. Reset Alignment restores the defaults. These controls affect future conversions.
4. Enable **Convert After a Pause**, tap Done, write a short phrase with Pen/Pencil, and pause for 1.2 seconds. Existing ink is excluded when enabling conversion. Other tools pause automatic conversion.
5. Each recognized line becomes a separately editable text object, preserving its horizontal location and spacing from other lines. Use Select Objects or Inserted Content to edit the wording/style or move it. The All Content lasso can select converted text together with native ink and other objects; see [LassoSelection.md](LassoSelection.md).
6. Undo/Redo applies to the complete phrase, including all its lines. **Restore Original Handwriting** recovers the selected object's editable source strokes, including after reopening. Moving the text offsets its restored ink by the same translation; resizing text does not rescale source ink.
7. **Convert Existing Handwriting** explicitly attempts the page's current ink. It remains intended for short text-only pages, without lasso/paragraph selection.

The expanded built-in palette includes Noteworthy, Chalkboard SE, Marker Felt, Snell Roundhand, Bradley Hand, Chalkduster, American Typewriter, Cochin, Palatino, Georgia and Avenir wherever `UIFont` confirms availability. Imported faces and the current stored face are included in the picker. The same choices are available when editing a text object.

## Recognition and layout

The assistant debounces for 1.2 seconds and verifies the unchanged drawing prefix before recognizing appended strokes. `HandwritingRecognizing` exposes a line-layout result as well as its plain-text adapter. The Vision actor returns each observation's text and bounding rectangle converted to PencilKit's top-left logical page coordinates. Stroke centers are assigned to the closest recognized line; source ink is retained independently for every resulting object.

Rasterization normalizes a copy of the source to black on white under an explicit light trait collection, avoiding PencilKit's Dark Mode ink adaptation. Contextual whitespace improves short-phrase detection. The raster is capped at 2048 pixels, inputs at 1000 strokes/4096 logical points, and results at 12 observations. Every line must satisfy the confidence threshold and all stroke centers must lie near recognized regions. These are conservative geometry/confidence guards, not guarantees of semantic accuracy for cursive, diagrams or equations.

`HandwritingTextLayout` measures actual glyph-path bounds to choose a font size and measures the first baseline from the exact Core Text frame used by `PageElementRenderer`. It no longer places the first glyph by assuming the top of a text box is the ink's top. Separate text objects preserve gaps/indentation between recognized lines instead of reflowing a whole page in a single rectangle. Font sizes stay within 12–72 points, fit the available width and, when snapping, the paper line spacing. A phrase that cannot fit safely keeps all its original ink.

Snap guides match the renderer's 32-point ruled and 24-point grid lines, scaled dotted guides, and the actual lecture/Cornell writing regions. Headers, Cornell cues/summary, blank paper, PDF backgrounds and other templates have no inferred paper grid. A guide must be within 45% of its spacing; distant guides do not force a jump. The measured ink position is used without a guide. Descender geometry and the selected calibration influence the baseline estimate, so natural-writing acceptance remains necessary.

Source serialization and stroke comparisons run in utility tasks; rasterization/Vision and font file operations use separate actors. Text metrics and live canvas/model commits remain on the main actor. Before committing, the assistant rechecks page UUID, canvas identity, full drawing snapshot, cancellation/generation and foreground state. New ink, erasing, Undo, page/tool changes, leaving/backgrounding or changing recognition/layout settings invalidates pending results.

## Imported fonts and recovery

`HandwritingFontStore` coordinates security-scoped file reads, rejects non-font/collection/oversized inputs, parses the font descriptor and copies at most 10 MiB to an immutable relative path:

```text
Fonts/<SHA-256>.<ttf|otf>
```

Identical bytes share the same asset. A conflicting internal PostScript name is rejected instead of silently replacing another registered face. Fonts register for the current process and load again from their private copies after relaunch. The catalog also discovers Fonts directories beneath portable-backup restore prefixes, without traversing every notebook's images/PDFs. Imported files are retained; there is no automatic deletion or font-unregistration UI.

`PageElement` adds optional `fontFilePath`, `originalInkAnchorX` and `originalInkAnchorY` fields to the existing version-1 Codable envelope. Old objects decode with nil values. SwiftData schemas/entities, permanent page IDs and existing drawing paths are unchanged; no metadata-store migration or reset is required. The original optional `fontName` and embedded `originalInk` remain supported.

The initial converted object's origin is recorded separately from the source ink bounds. This prevents line alignment from shifting original strokes when they are restored; only a later user translation moves them. Legacy objects retain their previous restoration behavior.

Each line's native drawing is embedded and archived before removing any live strokes:

```text
Notebooks/<notebook UUID>/Handwriting/<text object UUID>.drawing
```

Text metadata commits first, followed by the existing drawing checkpoint/autosave pipeline. These two stores are not one filesystem/database transaction: a crash in between may leave duplicated ink/text, favoring recoverable data over loss. Source archives deliberately survive Undo, restoration and object deletion. Embedded source ink is limited to 8 MiB per object.

Font references are included in backup required-file validation, restored through the same relative-path remapping as image assets, and included in local upload preparation. Duplicating pages/notebooks shares immutable font bytes and preserves text/recovery metadata. No CloudKit transport is enabled. Page preparation, thumbnails and PDF export register required fonts before rendering; page/thumbnail fingerprints include font files so warm caches do not conceal missing or replaced assets. Missing/corrupt/mismatched fonts are reported and retained rather than silently removed. The shared Core Text renderer keeps canvas/thumbnail/export layout consistent and PDF text selectable.

## Verification

Automated coverage includes legacy Codable objects and optional-field round trips, invalid paths/nonfinite anchors, backup/restore font remapping and required assets, local upload font references, installed-font baselines (uppercase, accents and descenders), multiline spacing, blank/PDF behavior, calibration, compound Undo/Redo and moved/unmoved source restoration. A small original geometric TrueType fixture exercises actual Core Text registration, deduplication, source-file independence, restored catalog discovery, PDF embedding/selectable text, font errors and warm-page missing-file checks. It contains no third-party font data and is not shipped in the application target.

Native recognition still exercises the real Vision/PencilKit HELLO fixture and Dark Mode raster visibility. Those tests do not measure recognition accuracy across people's handwriting. Physical acceptance should cover natural Spanish/English cursive, descenders/ascenders on each paper type, phrase breaks, multiple lines, a personal font imported from Files, relaunch, Undo/recovery, editing during recognition, background/page/tab changes, PDF export and accessibility. Installation remains deferred at the owner's request.

Executed test results and build logs are recorded in [Validation.md](Validation.md).

## Apple references

- [Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- [VNRecognizedTextObservation](https://developer.apple.com/documentation/vision/vnrecognizedtextobservation)
- [Registering fonts for the current process](https://developer.apple.com/documentation/coretext/ctfontmanagerregisterfontsforurl(_:_:_:))
- [Apple font technology overview](https://developer.apple.com/documentation/technologyoverviews/fonts)
