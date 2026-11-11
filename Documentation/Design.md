# Visual direction — a quiet paper studio

The app should feel native, warm and personal while giving handwriting the most room. Use a warm off-white library background, sage accent, muted book colors and a restrained system-serif accent for short editorial text. Keep navigation, search, forms, symbols, sheets and menus native. Avoid ornamental animation, gradients, fake activity and invented study progress.

## Implemented refinements

- Library notebook covers sit directly on the background instead of inside a second card. A spine, fine page edge and single title initial give a book-like identity without textures or bitmap assets. Notebook titles appear once below the cover. PDF and favorite states are real metadata.
- Adaptive grid columns are narrower, with more separation and a comfortable maximum content width.
- Empty Library and Favorites states explain their actual next action. Search uses the native no-results state. Study remains clearly marked as coming soon.
- Notebook creation shows a live cover preview and directly selectable color circles with checkmarks. Cover color is never the only indication of selection. Preview dimensions are explicit so its GeometryReader cannot overlap neighboring form rows.
- The editor keeps the existing single-row header and 52-point page bar. A small cover-colored mark ties it to its notebook; tools sit in a quiet control surface and their selected background moves briefly between tools.
- A muted canvas surround and subtle paper shadow separate the sheet from controls without changing exported backgrounds or ink. Dark mode uses a brighter sage accent for contrast. Paper remains white to preserve ink appearance.
- Library buttons have a small press response and native pointer hover. Reduce Motion disables the added press scale and tool-selection animation. No decorative animation runs while writing.

## Scope and validation

These changes affect views and theme only. The metadata schema, PDF rendering geometry, drawing files and save/export services are unchanged. The Xcode project registers the new NotebookCover and LibraryEmptyState views without changing signing settings.

Simulator and signed device builds pass. The empty Library and creation form were inspected through Device Hub; title entry and accessible color controls were checked. Full verification on hardware of populated grids, long titles, very large Dynamic Type, dark appearance and tool interaction remains necessary. Existing persistence and document tests were not repeated for this presentation-only change.

## Manual review

1. Create notebooks with each cover color, long titles and non-Latin initials; verify previews, grid layout and VoiceOver names.
2. Check Library, an empty folder, Favorites and a search with no results.
3. Rotate and resize the iPad, then enable dark mode, large Dynamic Type, increased contrast and Reduce Motion.
4. Open an ordinary notebook and a PDF notebook. Confirm the header stays in one row, tools remain horizontally reachable, and handwriting/zoom/page turns behave as before.
5. Inspect cover contrast, paper separation and selection states on the physical display; adjust the palette based on that review rather than adding more effects.

Reference: [Apple's guidance on purposeful motion](https://developer.apple.com/design/human-interface-guidelines/motion/).

## Editor page controls — November 9, 2026

The previous bottom page bar has been removed. Add Page and the compact page counter/grid button now sit at the trailing end of the top editor header, next to Page Options. Tapping the counter opens the existing thumbnail browser, with Previous/Next arrows above its grid. Finger page turns and all save-before-navigation services are unchanged. No controls remain below the canvas.

Regular-width windows use one header row; compact windows keep notebook identity/page actions on the first row and horizontally scrollable tools on a second top row. The tools scroller has an explicit 52-point height to avoid claiming excess vertical space. Buttons retain 44-point touch heights and accessibility names. No metadata, drawing or PDF storage changes are involved.

Validation: simulator and signed device builds passed, and the update installed successfully on the connected iPad Air. No new unit tests were added for this view rearrangement. Manual acceptance remains: check Add Page, open/select thumbnails, Previous/Next boundaries, long notebook titles, narrow windows, landscape/portrait and writing near the bottom edge; verify that the lower canvas area remains unobstructed. The earlier single-row/bottom-bar review notes above describe the prior layout.

Delivery: the signed update installed successfully over the existing Notes app on the connected iPad Air, with the same bundle identifier. The full Phase 3 implementation is included in this build; its previous device delivery had been deferred while the iPad was unavailable.
