# Compact editor menus

## Primary actions

The tab strip's ellipsis has five visible first-level entries: Add Page, Focus Mode, Export PDF, Page and Workspace. Two inline native UIMenu groups separate immediate actions from secondary categories. The native button, 44-point touch target and current popover styling remain in use.

Page offers either Page Template for ordinary paper or PDF Note Margin for PDF-backed pages. Inserted Content appears when the current page has objects. Duplicate, move earlier/later and confirmed deletion remain here for the current page.

Workspace contains Toolbar Position, Quick Palette, Recently Opened when populated, Draw with Finger and Save Now. An unsaved page with an error offers Retry Saving. Quick Palette retains show/hide and position restoration, so it can always be recovered after hiding. Settings remains in the app sidebar, and Ruler remains in the shapes/tools menu.

## Contextual access

Each page thumbnail's native context menu now offers Duplicate Page, Move Page Earlier, Move Page Later and Delete Page, alongside existing bookmark and section commands. Those actions target the thumbnail's permanent page ID, including when another page is open. Deletion requires confirmation and the last page cannot be removed. Drawing files remain locally available for recovery, as with the previous current-page deletion workflow; page metadata is still removed.

The floating palette has Restore Position alongside its existing corner placement, profiles and favorite-editing controls. The toolbar's palette button also retains its recovery context action.

## Export choices

Export PDF initially provides Current Page and Entire Notebook. Practice appears only when study tape is present. Covered current-page export is offered only when the current page contains tape; covered notebook export also appears when another page contains it. Current in-memory objects are used for the active page, and other page snapshots are inspected off MainActor. UIKit's iPadOS 15+ uncached deferred menu provider performs that inspection when Export is opened instead of on every parent editor update. Actual export keeps its save boundary, original-PDF geometry and error handling.

## Page-operation safety

EditorSession accepts an optional page target for duplication/deletion and a target for movement while preserving existing current-page calls. It validates notebook membership and flushes current ink before duplication or deletion. Duplication also checks the source's standard fallback drawing path if its metadata path is nil, retaining crash-recovered ink. It creates independent drawing files and object IDs while preserving the source page ID. Removing another page preserves the current canvas/ink; removing the current page clears the deleted model reference before committing and opens a surviving page. Failed saves block duplication/deletion. Moving pages preserves IDs and existing cross-section order semantics.

## Validation and review

Native tests verify the five-entry hierarchy, conditional paper/PDF options, hidden global settings/ruler duplicates, palette recovery through a real UIAction, context-sensitive practice choices, inactive-page duplication/reordering/deletion, retained ink files, last-page protection and save-failure blocking. Existing native activation, tab navigation, autosave, Pencil double tap, Focus Mode and PDF export checks are also retained.

On iPad, open the ellipsis and visit Page and Workspace. Hold a non-current thumbnail to duplicate or move it, cancel a deletion and verify the active ink stays intact. Hide and recover the palette. Compare ordinary/PDF pages, exports with/without study tape, and the menu with the toolbar docked at each edge. Changes are packaged in local scoped commits after user authorization; no push is performed.
