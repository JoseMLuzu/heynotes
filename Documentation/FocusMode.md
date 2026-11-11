# Focus Mode

## Workflow

Open **Page Options (the ellipsis beside the document tabs) → Focus Mode**.

The app hides its document tabs, navigation/header controls, main toolbar in any of its four positions, and library sidebar. The page gets the available editing space. The floating Quick Palette appears expanded automatically, including when it was previously hidden or collapsed. Page swipes, Pencil input, zoom, autosave and existing tools continue to use the same editor.

To leave, tap the inward-arrow icon at the top right of the palette, or choose **Exit Focus Mode** from its menu. No extra floating toolbar is introduced. The exit control is a native 44-point button with an accessibility label. In a window too small for the expanded palette, the compact header retains the exit control.

The palette cannot be hidden or manually collapsed while Focus Mode is active. This keeps a clear way out of the mode. Exiting restores the normal sidebar preference, toolbar position and the palette's previous hidden/collapsed state. Intentional changes to favorites, profile or palette position remain saved.

Focus Mode is runtime state for the current window/editor. Changing documents/leaving the document resets it, and a fresh app launch starts with normal navigation. Backgrounding/resuming the same live scene does not deliberately exit focus.

## Implementation

- `EditorFocusMode.swift`: small observable runtime presentation state, separate from notebook metadata and UserDefaults.
- `EditorView.swift`: retains the canvas's structural position while conditionally removing its existing safe-area tool/header insets. It requests status-bar and persistent system-overlay hiding using public SwiftUI APIs.
- `LibraryView.swift`: overrides split-view column bindings while focused, retaining normal layout state for restoration. It passes the same focus object into the editor.
- `FocusSplitViewPolicy.swift`: a noninteractive UIKit probe disables the containing UISplitViewController's sidebar edge gesture while focused, restoring its original `presentsWithGesture` value on exit/removal. Only public responder/controller APIs are used.
- `QuickPalette.swift`: focus overrides only the presented visibility/expansion, without rewriting saved palette visibility/collapse preferences. Its exit remains available if a page fails to load or the session is busy.
- `EditorPageMenu.swift`: adds the real Focus Mode action to the existing native Page Options menu.
- `EditorMoreButton.swift`: supports an SF Symbol parameter for the native exit control.

The mode does not create another editor, copy drawings, replace the canvas's Undo manager, alter page IDs, change templates or migrate/reset storage. System window controls and indicator behavior remain controlled by iPadOS; the app does not use private APIs to remove OS-owned window chrome. Reduce Motion and Reduce Transparency continue to use the existing palette policies.

## Verification

Three native focus tests exercise:

1. Entry through the actual native Page Options action; automatic palette presentation despite saved hidden/collapsed preferences; unchanged preferences, canvas identity, actual PencilKit ink and functional Undo; portrait/landscape layout; native exit activation; and an exit available when a page becomes unavailable.
2. Native sidebar gesture policy restoration for both an originally enabled and originally disabled policy.
3. The actual LibraryView/NavigationSplitView hierarchy: hidden app header/sidebar behavior, protected sidebar gesture and the same canvas across entry/exit.

Focus landscape, portrait, restored layout and complete library-host screenshots were exported and inspected. These tests use public control activation and view/controller inspection; they do not inject physical Pencil events or establish hardware frame-rate/latency.

## Physical acceptance

- Enter Focus Mode with the palette hidden and with it collapsed. Confirm it appears expanded, can move/change tools, and exits in one tap.
- Repeat with each main toolbar position and both sidebar states; confirm normal layout returns.
- Write, Undo/Redo with native iPad gestures, turn/create pages, pinch/scroll and rotate. Confirm all ink survives exit, background/reopen and PDF export.
- Check PDF note margins, short windows, Dark Mode, Reduce Motion/Transparency and VoiceOver.
- Confirm the sidebar cannot be revealed by an accidental edge swipe while focused.

Executed validation: all 74 native tests passed, including the three focus tests with actual nonempty PKDrawing content. The signed optimized Release build also passed. No persistent user data or schema was reset.

Delivery: the optimized Release build installed successfully on the paired iPad Air over the existing app, preserving its data container and preferences.
