# Navigation band and page ordering

The colored library navigation band extends 16 points downward below its controls/tabs. This extension uses AppTheme.headerBackground and follows the selected app accent in light/dark appearance. Library content retains its original 32-point inset. Folder navigation and the editor's Back to Library action use circular glass backgrounds consistent with the sidebar control. Materials remain noninteractive decoration, with Reduce Transparency and pre-iPadOS 26 fallbacks supplied by EditorGlassSurface.

The sidebar removes NavigationSplitView's default toggle using the public iPadOS 17 `toolbar(removing: .sidebarToggle)` API. The library supplies its own leading toolbar button; an open editor supplies its tab-row button. This leaves one toggle in the visible detail area. Compact-width sidebars retain a Close Sidebar action, and selecting a library destination returns to the detail column. See Apple's [toolbar removal documentation](https://developer.apple.com/documentation/swiftui/view/toolbar(removing:)).

## Fixed Pages index

The page counter opens a fixed popover anchored to that control. The panel has no drag grip, movement gesture or stored position. NotebookIndexView retains a 20-point horizontal header inset with additional vertical spacing. Done, selecting a page, tapping outside the popover or toggling the counter closes it. Existing section, bookmark and page context-menu operations remain available.

Touch and hold a thumbnail, then drag it onto another thumbnail to change its order. The destination highlights during a drag. Reordering commits on drop, so hovering or cancelling does not alter metadata. The moved page takes the target's original numbered slot: moving page 2 onto page 4 places it after the former page 4; moving page 4 onto page 2 places it before the former page 2. Dropping across sections adopts the target's section. The bookmark filter uses the same global order, including intervening non-bookmarked pages. Move Earlier and Move Later remain available in the context menu as alternatives to dragging.

## Identity, files and persistence

NotebookPageDrag is a Codable Transferable carrying only notebook/page UUIDs. Its custom content type is registered in Info.plist and has own-process visibility. No drawing, PDF, image bytes or filesystem paths travel through drag and drop. The app uses public [SwiftUI drag-and-drop APIs](https://developer.apple.com/documentation/swiftui/adopting-drag-and-drop-using-swiftui), available before the iPadOS 17 deployment target; availability was checked in the installed SDK.

EditorSession validates that one page reference belongs to the active notebook and that both pages still exist. It rejects busy/unavailable sessions, foreign notebooks, missing pages and self-drops. A successful move changes section membership and normalized contiguous pageIndex metadata, saves SwiftData and refreshes neighboring-page preparation. A metadata save failure uses the existing rollback/error path. There is no model migration or file move. Permanent IDs, bookmarks, drawing/PDF paths, the current canvas, undo history and pending ink stay intact. The existing checkpoint pipeline later writes pending ink to the same page's path. Grid animation is scoped to thumbnail order and respects Reduce Motion.

PageThumbnail uses its editor session's DrawingStorage rather than an unrelated global store, so previews and reorder targets resolve the same files as the live editor.

## Validation

Native tests decode an actual registered NSItemProvider reference, reorder in both directions and across sections, read persisted order through a new ModelContext, retain permanent IDs/bookmark/paths, preserve the live canvas and undo, and flush the latest pending drawing afterward. Invalid/busy/missing/self-drop cases leave order unchanged. A SwiftUI-hosted fixed-popover test verifies native UIDragInteraction/UIDropInteraction registration, anchored geometry through a reorder, and reuse of the active canvas. Library and index screenshots are visually reviewed. These checks exercise the transfer/ordering path but do not synthesize a physical long-press drag on iPad.

Manual acceptance: drag thumbnails forward/backward, cancel a drag, scroll to other pages, move across sections or bookmarked pages, confirm the numbered order after reopening the notebook, then write/undo/export. Check the extended colored band in Library, folders and accent/dark appearance. Changes are packaged in local scoped commits after user authorization; no push is performed.
