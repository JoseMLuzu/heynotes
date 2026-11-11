# Folder colors and application settings

## User workflow

Touch and hold a folder in the library or sidebar and choose **Change Color**. Eight curated colors are available: Sage, Blue, Teal, Lavender, Rose, Coral, Amber and Graphite. The folder cover and the solid 10-point dot before its sidebar icon share the same saved color. Each folder, including a subfolder, has its own color; moving or restoring it does not change that color. A selected folder retains the normal selection treatment, with its dot still visible. VoiceOver receives the color name as an additional value, so color is not the only identifying cue.

Open **Settings** at the bottom of the sidebar or from the editor's page-options menu. Settings includes:

- System, Light or Dark appearance.
- Eight accent presets and a native custom color picker. Choose **Apply Custom Color** after adjusting a custom color.
- Toolbar position, using the same preference as the editor's existing placement controls.
- The default paper for new notebooks: Blank, Ruled, Grid, Dotted or Cornell. Explicit template-gallery selections take precedence.
- Local-storage information and the installed app's actual version/build.
- **Reset Appearance**, which restores Blue and System appearance without resetting editor defaults or documents.

## Restrained visual treatment

The default app accent is a muted blue paired with porcelain-white library surfaces and pale blue-gray canvas surroundings. Dark appearance uses blue-gray neutrals. Header tint and controls use the existing adaptive palette.

The local preference defaults upgrade to version 2 once. An absent or invalid saved accent uses Blue. A stored legacy Sage accent upgrades to Blue on the first launch of this version. Other saved colors retain their values. Selecting Sage again after the upgrade persists normally across launches.

The application accent tints the library navigation bar, notebook tab strip and editor header. These surfaces blend 12% of the adaptive accent into the neutral app background, and the Settings preview uses the same color. Controls, selections and glass outlines also use the accent. Folder colors, page content and notebook covers use their own palettes.

`AccentPalette` limits saturation and derives light/dark foreground variants from the chosen hue. It also supplies stronger Increased Contrast variants using public UIKit traits. Tests sample 125 RGB combinations and check a minimum 4.5:1 foreground contrast against the neutral, selected and header surfaces under test. Very light, dark or saturated selections are adjusted intentionally. Native color-picker edits use a local draft so dragging does not repeatedly update the entire workspace.

`AppPreferences` caches the derived palette. Changes notify SwiftUI through Observation and persist in local UserDefaults. Editor toolbar preferences now share one observable instance, allowing Settings to update an open editor immediately. Changing the accent or toolbar position preserves the existing canvas identity and Undo history.

## Safe metadata evolution

Before editing the current models, an actual on-disk V4 fixture was captured with the previously shipped model definitions. It included folder hierarchy, a notebook, a section, a bookmark, inserted content and binary-file references. Its IDs and original ink bytes were retained for an independent upgrade check.

The former live V4 layout is now frozen in `Core/Persistence/SchemaV4.swift`. The current schema is V5 and adds only optional `Folder.colorRawValue`. A lightweight V4 → V5 stage follows the existing V1 → V2 → V3 → V4 stages. Missing or unknown color values display Sage; unknown values are not discarded merely by reading them. Existing model fields, relationship/delete rules, document paths and page IDs remain unchanged. No store reset or document-file rewrite is performed.

Folder color changes use the existing save/error/rollback path. A failed save keeps the previous color and displays an error. Application settings live separately in UserDefaults and require no document migration. Invalid saved application preferences fall back to safe defaults.

## Implementation map

- `Core/Models/ThemeColorValue.swift`: serializable RGB values and folder presets.
- `Core/Models/Folder.swift`: optional persisted folder color and safe accessor.
- `Core/Persistence/SchemaV4.swift`, `SchemaVersions.swift`, `PersistenceController.swift`: frozen V4 and V5 migration.
- `Core/Theme/AccentPalette.swift`, `AppTheme.swift`: cached adaptive foreground colors.
- `Core/Components/ColorChoiceButton.swift`: accessible reusable swatches.
- `Features/Settings/Services/AppPreferences.swift`: local appearance and paper preferences.
- `Features/Settings/Views/AppSettingsView.swift`: native settings and root appearance modifier.
- `Features/Library/Views/FolderColorPicker.swift`: folder color sheet and sidebar label.
- Library views/view model: settings access, color actions, tinted covers and new-notebook defaults.
- Editor preferences, page menu, glass capsule and page-creation indicator: shared settings access and restrained live tint.
- `NotesAppTests/FolderColorTests.swift` and `NotesAppDeviceTests/PersonalizationTests.swift`: migration, persistence, contrast, canvas preservation and native appearance checks.

## Validation and device acceptance

The independent fixture captured before changing the models successfully upgraded with stable IDs, hierarchy, page/section links, bookmarks, inserted-content bytes, document paths and unchanged ink bytes. Permanent tests also construct a frozen V4 store and verify migration, color save/reopen, Trash/restore and unknown-color fallback. The native migration test reopens an actual editable PKDrawing after upgrading.

The final host suite passes 26 tests. Native tests verify preference persistence/recovery, 125 sampled colors in light/dark appearance, and changing accents while preserving a real PKCanvasView, its drawing, ink-tool color and notebook edit date. Settings and library screenshots are attached to native test results and inspected visually.

On the physical iPad, verify these interactions with your own documents:

1. Change a parent folder and a nested folder to different colors; confirm their covers and sidebar dots update, including selected rows.
2. Close/reopen the app and restore a colored folder from Trash; confirm its color persists.
3. Open a written page, change the accent from Settings and return. Check ink, Undo/Redo and page switching.
4. Try a very light custom color and a dark color, Light/Dark/System appearance, Increased Contrast and large text. Confirm the controls remain readable and the workspace stays quiet.
5. Change toolbar placement and new-notebook paper. Confirm existing pages are unchanged and a newly created notebook uses the selected default.

Actual Apple Pencil interaction and subjective visual preference require physical-device acceptance; simulator tests do not establish device frame rate or handwriting latency.

Final verification: all 79 native simulator tests passed, followed by a successful signed optimized Release build. The Release app was installed over the existing iPad app with the same bundle identifier and retained data container (installation sequence 2564). The initial CoreDevice connection reset was resolved by retrying installation. Launch the updated app on the iPad to perform the acceptance steps above.

## Soft-blue default — 2026-11-11

The revised palette and one-time legacy-Sage preference upgrade passed all 83 native simulator tests. Tests also verify that a subsequent Sage selection persists and an existing Lavender selection survives the upgrade. Default-blue editor/library screenshots and light/dark Settings screenshots were inspected. The signed Release build succeeded and was installed on the connected iPad with CoreDevice installation sequence 2644.

## Leading folder dots — 2026-11-11

Sidebar color dots now precede the folder icon and title. The marker uses a solid 10-point vector circle. Removing the former translucent 0.7-point white border and increasing the diameter gives it a cleaner edge. Each row combines its accessible label and color value and retains a full-width hit area. All six native personalization tests pass; real library sidebar captures were inspected in Light and Dark appearance. The signed Release update was installed on the connected iPad with installation sequence 2652.
