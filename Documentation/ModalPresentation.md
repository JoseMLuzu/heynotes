# Modal presentation

## Presentation policy

App-owned sheets use two policies. Long forms open expanded, avoiding the previous half-height presentation that required manual expansion. Short dialogs use a compact initial size so a single input does not sit above a large unused area.

`appSheetPresentation()` retains page sizing and a single Large detent for New Notebook, Settings, Quick Palette, Palette Profiles, Edit Favorite, inserted-content editors, Handwriting Style and PDF page selection. Their native Form, List and ScrollView containers retain scrolling and keyboard avoidance.

`compactAppSheetPresentation(idealHeight:)` is used by:

| Form | Initial height at standard text size |
| --- | --- |
| Create folder/subfolder and rename dialogs (`TitleForm`) | 200 pt |
| Folder Color | 430 pt |
| PDF Note Margin | 470 pt |

Compact sheets use a preferred width of 440 pt and a scaled ideal height on iPadOS 18 or later. These are layout preferences, not fixed view frames; the system can adapt to the presenting window and keyboard. Their single height detent also provides an iPadOS 17 fallback. The existing scroll containers handle content overflow. Accessibility text sizes use the expanded policy so controls and long labels remain reachable.

The native PDF share controller, photo/file pickers, alerts, tool popovers and full-screen cover/template galleries retain their separate platform presentations. There are no global UIKit appearance changes, persistence changes or schema migrations.

## APIs and compatibility

The project targets iPadOS 17. `presentationDetents` is available at this target. `presentationSizing`, `.page` and `.fitted` are guarded with an iPadOS 18 availability check, verified against the installed SDK interface. Apple documents content-based ideal sizing in [FittedPresentationSizing](https://developer.apple.com/documentation/swiftui/fittedpresentationsizing) and [presentationSizing(_:)](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:)). NavigationStack and Form are flexible containers, so the compact policy supplies an ideal size for the fitted presentation.

## Verification and manual acceptance

`ModalPresentationTests` presents actual app forms through native SwiftUI sheets. It checks compact versus expanded initial height, containment within the presenting window, keyboard focus/input visibility for title dialogs, landscape and narrow-window sizing, and the expanded accessibility-text fallback. Screenshot attachments support visual inspection of New Folder, Rename, Folder Color, PDF Note Margin, New Notebook and Settings.

On iPad, open New Folder, New Subfolder and Rename: confirm the input and Cancel/Save actions are visible without expanding the sheet. Enter a long title, show the keyboard, rotate and use a narrow window. Check Folder Color and PDF Note Margin scrolling. Open New Notebook, Settings and PDF page selection to confirm long forms still have sufficient initial space. Repeat with larger accessibility text. Saving, cancelling and returning to the editor must preserve existing document data.

Runtime validation uses iPadOS 26.5; the iPadOS 17 fallback is compile-checked rather than runtime-tested.
