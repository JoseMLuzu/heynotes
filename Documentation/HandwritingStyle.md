# Handwriting Style — experimental prototype

## Scope and availability

This is opt-in handwriting-to-text conversion with an installed handwritten font. It is not ink smoothing, Smart Script, a personal handwriting model, or mathematical notation recognition. The original PencilKit editor remains the default. Conversion is off in each new editor session; the selected font and recognition language persist locally.

The installed toolchain is Xcode 27.2 / Swift 6, with an iPadOS 17 deployment target. The connected iPad Air runs iPadOS 26.5. The implementation therefore uses public Vision `VNRecognizeTextRequest`, available on the existing deployment target. It does not call the iPadOS 27-only `PKStrokeRecognizer`. `HandwritingRecognizing` allows a later stroke-recognition adapter without changing document models or SwiftUI.

Recognition and font rendering run locally. There are no remote APIs, accounts, external models, new packages, or font downloads. This prototype offers English and Spanish recognition. The font picker lists only faces that `UIFont` confirms are installed: Noteworthy, Chalkboard SE, Marker Felt and Snell Roundhand, where available. Unsupported stored font names fall back to the system font.

## User workflow

1. Open a notebook, choose the Insert menu (`plus.square`), then **Handwriting Style**.
2. Select a font and recognition language. Enable **Convert After a Pause**, then tap Done.
3. Write a short phrase with Pen or Pencil and pause for 1.2 seconds. Existing ink is excluded when enabling the mode. While enabled, the Insert button uses a tinted text icon so the active mode remains visible without another toolbar item.
4. The phrase becomes an editable text object. Use Select Objects or Inserted Content to move, resize, change its font or correct recognition errors.
5. Use Undo to restore the preceding ink/text state in one action. Alternatively, edit the converted text and choose **Restore Original Handwriting**; this remains available after closing/reopening the notebook. Moving the text moves the recovered ink to the text's new location. Resizing the text does not rescale its source ink.
6. **Convert Existing Handwriting** explicitly attempts the current page's ink. This action is best for short, text-only pages; it does not select individual paragraphs or a lasso region.

Switching to highlighter, eraser, lasso, shapes or object tools pauses automatic conversion and resets its baseline. Returning to Pen/Pencil starts a new phrase. Changing font/language also resets the baseline: pending ink stays as ink. Page/document navigation, leaving the editor, and backgrounding invalidate pending recognition. Mode activation is not carried across separate document sessions.

## Recognition and responsiveness

The assistant debounces for 1.2 seconds, validates that the existing drawing is still an unchanged prefix, and recognizes only appended strokes. The raster/Vision adapter executes on a dedicated actor. Source serialization and prefix/suffix comparisons run in detached utility tasks. No SwiftData model or live canvas crosses actors.

Ink color is normalized on copies of the native strokes, retaining their metadata and leaving stored ink unchanged. Both PencilKit rasterization and white-paper compositing run inside an explicit light `UITraitCollection.performAsCurrent` context. PencilKit otherwise adapts black ink to white in Dark Mode, which can produce an empty white-on-white OCR image. The crop includes adaptive whitespace, which is necessary for the text detector to recognize short phrases reliably. The raster is capped at 2048 pixels on its longest side. Inputs are limited to 1000 strokes and a 4096-point bounding dimension; results are limited to 12 lines. All lines must meet a confidence threshold, and all stroke centers must fall near recognized text regions. These checks reduce accidental conversion of drawings, but they do not establish semantic correctness. Low-confidence/unsupported results keep the ink and expose a nonmodal status in the settings sheet.

Every result is checked against the current page UUID, canvas identity, drawing snapshot, cancellation token and foreground state before committing. New strokes, erasing, undo, page switches and mode/tool changes invalidate work. Recognition cannot replace a newer drawing.

The layout is approximate: line breaks are retained, but fonts reflow text inside an editable rectangle. Conversion is skipped if the text cannot fit below its original position. Character positions, pressure, personal letter shapes, equations and diagrams are not preserved as font glyphs. Use short phrases and inspect recognized text. Actual cursive accuracy and latency require testing with a physical Apple Pencil; the synthetic recognition fixture is not an accuracy benchmark.

## Persistence and recovery

`PageElement` gains two optional Codable fields: `fontName` and `originalInk`. Missing fields decode as nil, preserving existing version-1 object envelopes. SwiftData entities, frozen schemas, relationships, page UUIDs and original drawing paths are unchanged; no store migration/reset is required. Duplicating pages/notebooks preserves these fields through the existing codec.

Before removing strokes, conversion atomically archives their PKDrawing representation to a unique relative path:

```text
Notebooks/<notebook UUID>/Handwriting/<text object UUID>.drawing
```

The same editable source is embedded in the text object, so recovery continues to work when duplicating a notebook. Font names are capped at 128 characters and embedded source ink at 8 MiB. The archive is deliberately retained after undo, restoration or object deletion; no automatic garbage collection is introduced.

The compound edit saves text metadata first and then changes the live PKDrawing, which follows the existing autosave/checkpoint pipeline. Ink/text Undo uses one action, including Redo. A crash between the metadata save and the ink checkpoint can leave both original ink and converted text visible. This prototype favors recoverable duplication over losing source strokes; metadata and FileManager writes are not a cross-store transaction. Embedded source plus retained immutable archives allow recovery even after an intervening edit/undo. Deleting the converted text intentionally removes its embedded source from the document, but the retained archive remains in private storage for manual recovery.

The shared `PageElementRenderer` resolves the same font for canvas objects, thumbnails and PDF export. PDF text remains selectable; the source ink is recovery metadata and is not drawn or exported a second time.

## Verification

Host coverage checks legacy JSON decoding, optional-field round trips and invalid font metadata rejection. Native coverage exercises:

- Conversion, one-action Undo/Redo, checkpoints, reopening, retained archives and original-ink restoration.
- Stale snapshots, non-suffix source strokes and cancelled commits retaining all ink.
- Debounced new-ink conversion with existing ink preserved; highlighter excluded.
- Pending recognition discarded after switching pages.
- Unrecognized results preserving the original drawing.
- Actual Vision recognition of a deterministic PencilKit block-letter fixture, plus empty input.
- Installed fonts, PDF dimensions/selectable text, and native settings/PDF screenshots.

Manual acceptance on the physical iPad should include natural cursive in both languages, light colors, long pauses within a word, diagrams/formulas, editing during recognition, tool/page/tab switches, Undo/Redo, app backgrounding, reopening, duplicate notebooks, PDF export, dark mode, large text and VoiceOver. Personal handwriting font creation, continuous word joining, line-level selection, and native iPadOS 27 recognition are future work.

## Executed validation — 2026-11-10

- **PASS:** 24 host tests (23 Swift Testing tests plus one XCTest metadata compatibility test).
- **PASS:** 58 native tests on the iPadOS 26.5 simulator, including seven handwriting tests. Real Vision recognized the constructed PencilKit HELLO fixture after the adaptive crop correction.
- **PASS:** signed generic iPadOS build with deployment target 17.0.
- **PASS:** installation on the connected iPad Air (5th generation), iPadOS 26.5. Existing application data was preserved; no uninstall or store reset occurred.
- Native settings and the four-font exported PDF were visually inspected from XCTest attachments. Real Pencil cursive accuracy and interaction remain a physical-device acceptance task; installation does not establish that accuracy.

New production files are `HandwritingAssistant.swift`, `HandwritingRecognition.swift`, `HandwritingFont.swift`, `StrokeContent.swift`, `EditorHandwriting.swift`, and `HandwritingStyleView.swift`. Existing editor/session, text-object UI, shared renderer and workspace lifecycle were extended. `HandwritingTests.swift` and `HandwritingMetadataTests.swift` cover the new behavior.

## Apple references

- [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- [Supported recognition languages](https://developer.apple.com/documentation/vision/vnrecognizetextrequest/supportedrecognitionlanguages())
- [PKStrokeRecognizer](https://developer.apple.com/documentation/pencilkit/pkstrokerecognizer)


## Dark Mode OCR correction — 2026-11-10

A user-reported failure with Apple Pencil exposed an appearance-dependent rasterization bug. A local, read-only diagnostic copy of the latest iPad drawing reproduced an empty OCR image: black normalized ink was adapted to white by PencilKit. Forcing a light rendering appearance restored visible handwriting and real Vision detected text in that diagnostic page. No user strokes or device documents were modified by this investigation.

A native regression test under an explicit dark trait environment failed before the fix with zero dark pixels in the OCR raster, then passed after the correction. All eight focused handwriting tests pass, including actual Vision recognition, ink restoration, Undo/Redo and stale-result rejection. Physical Pencil interaction still requires user acceptance; these results do not establish recognition accuracy for every handwriting style.

The change is confined to the temporary recognition image and its test. The application's theme, canvas, saved ink and export format remain unchanged.

The signed correction build and installation on the connected iPad Air (iPadOS 26.5) succeeded. Temporary note-derived diagnostic copies were removed from the Mac after verification.
