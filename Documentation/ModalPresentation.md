# Expanded modal presentation

## Problem and behavior

Library forms and folder colors explicitly offered Medium and Large detents, so the system could open them halfway. Other app-owned forms used automatic sheet sizing, producing inconsistent usable height on iPad. Users had to expand panels before working through their contents.

All app-owned sheet roots now use `AppSheetPresentation`. They open at the system's large height, with page sizing on iPadOS 18 or later and a large-detent fallback on iPadOS 17. There is no intermediate half-height stop. Native Form, List and ScrollView containers still scroll when content exceeds the available height, including with the keyboard or larger text. Navigation actions and native dismissal remain available.

The policy is applied to New Notebook, folder creation/renaming, Folder Color, Settings, Quick Palette, Palette Profiles, Edit Favorite, PageElementEditor, Inserted Content, Handwriting Style and PDF Note Margin. Applying it to each sheet root also covers the existing nested palette/content editors. It does not add fixed screen dimensions or global UIKit appearance changes.

The native PDF share controller, photo/file pickers, alerts, tool popovers and existing full-screen cover/template galleries retain their platform-appropriate presentations. Their sizing is separate from app form sheets.

## APIs and compatibility

`presentationDetents` is available below the project's iPadOS 17 minimum. `presentationSizing` and `.page` are guarded with an iPadOS 18 availability check; availability was also checked against the installed Xcode SDK interface. Apple documents page sizing for informational/compositional content in [presentationSizing(_:)](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:)).

No metadata, drawing persistence, autosave or document migration changes are involved.

## Verification

`ModalPresentationTests` presents the actual app forms through SwiftUI sheets, rather than rendering form contents as standalone hosting views. It checks their initially visible height without any expansion gesture and verifies their lower edge stays within the presenting window. Additional Settings cases use landscape and a narrow window; native presentation attachments support visual inspection.

Physical-device acceptance: open New Notebook, folder colors and Settings from the library; open palette management, favorite editing, handwriting style and inserted content from the editor. Confirm each starts expanded, scrolling works, controls remain reachable with the keyboard, nested editors dismiss back to their parent and the drawing remains unchanged after returning.

Final automated validation (2026-11-10): all 81 native simulator tests pass, including two presentation tests that exercise the 11 real app forms and additional landscape/narrow-window cases. Native New Notebook and Settings presentation screenshots were visually inspected. The optimized signed Release device build succeeds. The iPadOS 17 fallback is compile-checked; runtime presentation checks used iPadOS 26.5.

The Release update was successfully installed on the connected iPad over the existing app (CoreDevice installation sequence 2572), without uninstalling or resetting its data.
