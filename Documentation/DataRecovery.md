# Recoverable page removal

## Migration plan — November 26, 2026

Freeze the shipped V8 user-store layout before changing any live model. V9 adds only optional NotePage.trashedAt, defaulting to nil. Use a lightweight V8 → V9 migration; retain every existing UUID, relationship, page position, file path, journal revision and asset. Keep V1–V7 snapshots unchanged. The account-state sidecar is independent and unchanged. Verify migration from an actual V8 disk store, not only from an in-memory fixture.

Page removal becomes a metadata upsert in the same explicit journal/save transaction. Keep the page attached to its original notebook/section, with its last active index and all content. Active navigation, counts, PDF export, thumbnails and Study source opening exclude removed pages. Restore reuses the same page ID and files and inserts near its saved position within its section. Retain at least one active page. Expose removed pages in the notebook's Pages panel; no permanent deletion or automatic expiration is introduced.

Backup manifest version 3 carries the optional removal timestamp. New builds must read versions 1–3; older builds reject v3 rather than silently resurrect removed pages. Both current and removed pages and all their assets are backed up. Local sync snapshots retain removal state as an upsert; no live cloud protocol is enabled.

Before considering the migration accepted, test disk reopen, editable ink, PDF/image metadata, stable Study source IDs, reorder/delete/restore, failed saves, backup/restore into empty and populated stores, legacy archives and migration retention of journal entries. Physical Files-provider restore and power-loss/upgrade trials remain separate acceptance tasks; do not reset or uninstall the owner's app to test them.

## Implemented behavior

Pages → Recently Deleted lists retained pages with their removal date, preview and Restore action. Dynamic Type accessibility sizes place the action below the content. Restoring does not automatically open/overwrite the current canvas. The notebook retains at least one active page; no automatic expiry or permanent-removal operation is introduced. Removing a section nullifies the retained page's section relationship; restoration then uses Unsectioned Pages. Restore inserts near the saved active index and normalizes section order, without claiming an exact historical order after intervening reordering/removals.

Notebook.pages includes both active and retained pages for relationship ownership, migrations, file-safety checks and portable snapshots. Notebook.orderedPages and activePageCount exclude retained pages. Removed pages remain upserts in the passive sync journal. Study source resolution rejects a retained page until restoration; the card's IDs are never rewritten. Duplicating/exporting a notebook includes active pages only. Library backup includes both.

V9 applies to existing stores on their next open. Its migration is verified against all eight V8 entity hashes captured independently from the unmodified global models at Git commit 743c556; PageRecoveryTests stores those hashes and migrates a V8 disk library with source links and a pending revision. V1–V7 schemas and the sync-state sidecar remain unchanged. This is not acceptance of an in-place physical-device upgrade.

## Limits and physical acceptance

This cannot recreate pages removed before recovery metadata existed. Preserved old drawing bytes remain untouched, but an orphan file is not a restorable page. Use an earlier library backup if available. Backup v3 is readable by this build; older apps reject it. Keep an earlier backup until checking the upgrade. No crash/power-loss transaction journal across filesystem and SwiftData is claimed; a retained orphan after interruption is preferable to deleting user bytes.

On a physical iPad, using copies of test notes:

1. Create three pages with Pencil ink, PDF annotations, an image, a section/bookmark and a linked flashcard. Save a backup externally through Files before removal.
2. Remove the middle page and relaunch offline. Confirm only active pages appear in navigation/PDF export; Study reports the source unavailable without changing the card.
3. Open the notebook's Pages → Recently Deleted, restore and confirm editable ink, PDF geometry, section/bookmark and the same card source. Try reordering, removing a section and restoring again.
4. Make a new external backup containing a removed page, inspect the real preview counts and restore it into an isolated test library. Verify both original notes and independently restored copies after relaunch. Do not uninstall the owner's app to obtain an empty library.
5. Test cancelled/failed Files-provider export, damaged backup copies and low-space/interrupted restore on a test device. Keep original archives. Record device/build/results in Validation.md; automated simulator checks do not complete this gate.
