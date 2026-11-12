# Apple Pencil double tap

The editor installs one public UIPencilInteraction on its active PageCanvasContainer. It works with handwritten and PDF-backed pages, including object-tool selection and Focus Mode. No PKToolPicker is required and no document schema changes are introduced.

## System preference

The delegate reads UIPencilInteraction.preferredTapAction at the time of each event, so a change in Settings applies without an app preference overriding it.

| Preferred action | App behavior |
| --- | --- |
| Switch eraser | Toggle between the eraser and the last non-eraser tool. |
| Switch previous | Toggle between the current and previous tool kinds. |
| Show color palette | Select the last ink-capable tool when necessary and toggle the existing color/width/opacity panel. |
| Show ink attributes | Toggle the existing selected-tool settings, including eraser settings. |
| Show contextual palette | Toggle the floating favorites palette; in Focus Mode, toggle tool options because favorites are already visible. |
| Ignore or system shortcut | Do not alter app tools; shortcut execution belongs to the system. |

Tool history is local to the retained editor controls and includes manual tool selection and palette tool changes. Each tool keeps its existing saved color, width, opacity and eraser settings. History records tool kinds rather than two presets of the same pen kind. A fresh editor starts with the eraser/pen as the previous-tool fallback; history does not add fields to saved document metadata.

The active canvas gates callbacks during loading, page transitions and an in-progress Pencil stroke. The editor also rejects actions during document switching, export and its document-editing presentations. Hidden, detached or disabled interactions do nothing. The handler changes the shared ToolPreferences used by both toolbar and PencilKit, retaining the current canvas, drawing and Undo history. The interaction is detached when its representable is dismantled.

## Availability

The deployment target remains iPadOS 17. The installed iPadOS 27.2 SDK exposes pencilInteraction(_:didReceiveTap:) and init(delegate:) from iPadOS 17.5. That callback is used on modern systems. The deprecated pencilInteractionDidTap(_:) declaration is retained solely for iPadOS 17.0–17.4; Apple specifies that only the modern callback is delivered when both are implemented. This fallback is compile-checked against the configured target; runtime automation uses iPadOS 26.5.

## Acceptance

On a compatible Apple Pencil, choose Switch Between Current Tool and Eraser in Settings → Apple Pencil. Open a note or PDF, choose the highlighter, double-tap the Pencil's side, erase, then double-tap again. The highlighter must return with its original style. Repeat with Previous Tool, Show Color Palette, Off, a docked toolbar and Focus Mode. Verify Undo/Redo, page changes and background/reopen. The simulator cannot produce a physical Pencil double tap: automated tests invoke the same action-routing path on the installed native interaction and real canvas; hardware gesture recognition requires the device check.

## Automated verification

PencilDoubleTapTests covers tool-kind history and saved style preservation, system-action routing and disabled/system-owned actions, and the installed native interaction on a real PKCanvasView. The native test checks eraser/highlighter updates, unchanged drawing/canvas/Undo, loading/disabled guards, color-panel open/close and Focus Mode presentation. It disables UIKit animations only inside its temporary test window and restores the previous setting on exit, so it tests presentation completion without relying on simulator transition timing. The Focus Mode color-panel screenshot is captured from the actual window and visually reviewed.

## Apple references

- [UIPencilInteraction](https://developer.apple.com/documentation/uikit/uipencilinteraction)
- [Preferred tap action](https://developer.apple.com/documentation/uikit/uipencilinteraction/preferredtapaction)
- [UIPencilPreferredAction](https://developer.apple.com/documentation/uikit/uipencilpreferredaction)
