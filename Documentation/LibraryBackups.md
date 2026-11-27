# Library backups

The first CloudKit preparation milestone provides an actual exportable and restorable local library. It does not enable cloud synchronization, change the SwiftData schema, or send data to a service.

## Using it

Open **Settings → Backups → Create Library Backup**. HeyNotes saves pending handwriting in both visible editors, prepares a `.heynotesbackup` file, then opens the native Files export picker. Choose a location outside the application, such as an external drive. Success is shown only after the picker confirms a destination; cancelling does not claim that a backup was saved.

Choose **Restore from Backup**, select a `.heynotesbackup` file, inspect its date and actual counts, and tap **Restore Library**. Preparation checks the entire file before offering restoration. Restore is additive: existing metadata and files remain intact. Restoring the same archive twice intentionally creates two copies rather than deduplicating or updating existing notes.

Restore into an empty library retains original model UUIDs. Where an incoming UUID already exists, only the incoming record receives a fresh UUID. Folder, notebook, section, page, deck, card and review relationships, including card source links, are remapped together. A previously missing source remains an optional UUID reference, as in normal Study behavior.

## Contents and scope

Included:

- Every stored folder, notebook, section and page, with raw cover/template/color values, bookmarks, ordering, timestamps, favorites, optional ownership and Trash state.
- Editable per-page drawing bytes, original PDF sources and image assets. Multiple page references to one PDF remain shared within the restored copy.
- Inserted objects, including text, shapes, tape, fonts and preserved original ink from handwriting conversion.
- Study decks, cards, source references, scheduling state and review history, including Study Trash.
- All regular files in the private document storage root, including prior `.backup` drawing checkpoints, preserved damaged files and retained files without current metadata references. This deliberately favors recovery over automatic cleanup.

Not included: appearance preferences, toolbar/palette preferences, open tabs, transient Undo history, rendered caches, the SQLite implementation files or bundled cover artwork. User-created content is portable; preferences remain local. A retained orphan file stays preserved in the restored namespace but is not automatically turned into a new page.

The archive checks byte integrity, relationships and inserted-object envelopes. It does not establish that every existing PDF or drawing is semantically readable; damaged bytes are retained for recovery. A missing explicitly referenced drawing, PDF or image causes the complete backup to fail visibly instead of reporting a misleading partial success. Unknown inserted-object envelope versions also fail explicitly.

## Architecture

`BackupMetadataStore` is a SwiftData model actor. It converts model objects into `BackupManifest` value records and creates restored records in an isolated context. No model object crosses actor boundaries. `LibraryBackupService` coordinates this actor with the existing `DrawingStorage` actor.

`DocumentWorkspace.withSavedLibrary` blocks document navigation and editor interaction, cancels handwriting conversion/preparation work, captures the live native canvases even when their final delegate callbacks are still queued, flushes both sessions, then saves the main metadata context. The boundary holds until archive creation or restoration finishes and retains the current canvas instances. A failed save stops the operation while preserving pending ink in memory. Service callers outside this UI boundary must ensure their own editors and metadata mutations are quiescent.

The file snapshot/install runs synchronously on `DrawingStorage`'s executor so drawing writes cannot interleave with it. Bulk copies and SHA-256 hashes use 1 MiB chunks off the main actor. Metadata is an in-memory JSON manifest, capped at 64 MiB; model records and file entries are capped at 200,000 per collection. These are explicit first-version limits, not a constant-memory guarantee for arbitrarily large libraries.

The application exports a temporary archive through `UIDocumentPickerViewController(forExporting:asCopy:)`, avoiding a whole-archive `FileDocument`/`Data` buffer. Source URLs use security-scoped access and coordinated reads. The custom public data UTI is `com.local.notesapp.library-backup`.

## Archive format, record version 3

The format is an uncompressed, unencrypted sequential container, not a ZIP file. SHA-256 detects accidental corruption; it does not authenticate a sender. Treat a backup as a copy of private notes when choosing a destination.

All lengths/counts are unsigned 64-bit little-endian integers:

1. Eight container magic bytes: `HEYBKP01` (unchanged).
2. Manifest byte length, its 32-byte SHA-256 digest, then UTF-8 JSON bytes.
3. File count.
4. For each file: UTF-8 relative-path byte length, path bytes, file byte length, 32-byte SHA-256 digest, then file bytes.

JSON uses Foundation's default Codable Date representation (seconds since the reference date). Export sorts JSON keys and file paths. Import rejects unsupported versions, malformed/truncated data, unexpected trailing bytes, invalid object graphs, folder cycles, path traversal, symlinks and case/Unicode-equivalent file path collisions. File lengths must fit within the remaining archive. Both `/var` and `/private/var` temporary-directory aliases are normalized when computing relative paths.

## Restoration and failures

The entire archive is extracted and verified into an application-owned temporary directory before a restore preview appears. Installation verifies staged file sizes/hashes again and moves assets under a fresh `Restored/<UUID>/` namespace. Stored drawing, PDF and image paths are rewritten relative to the private document root. Deterministic drawing files without a saved metadata path are adopted when present, covering an interrupted first drawing checkpoint.

The metadata actor inserts the complete restored graph and performs one explicit context save. On save failure it rolls back only its isolated context and removes only this attempt's new file namespace. Existing rows, existing files and other contexts' unsaved changes remain untouched. Temporary cleanup is restricted to directly owned `HeyNotesBackup-*` directories. Picker cancellation and dismissed restore previews release staged files.

SQLite and the filesystem do not share a transaction. Process termination after the file move but before metadata commit may leave an unreferenced restored directory; it does not overwrite the existing library. No automatic orphan purge or cross-store recovery journal is claimed. The original archive is never edited, so a restore can be retried after an interruption. If commit completed, retry adds another copy. A future recovery journal should precede automated background imports.

Allow disk space for the archive plus staged extracted assets. Version 1 does not compress large PDFs, provide password protection, automatically schedule backups, merge restored records, or include cloud sync. Cancellation is checked during streaming, between pages and before commit; the current UI keeps critical operations open rather than offering unsafe interruption controls.

## Verification and manual acceptance

Host tests exercise disk-store reopening, nested folders and Trash, per-page ink, chunked image bytes, original PDFs, implicit drawing paths, retained files, duplicate-ID remapping and Study history. Negative fixtures cover truncated/corrupted archives, future versions, missing assets, traversal, case collisions, cycles, symlinks, staged tampering, cancellation and failed metadata saves.

Native tests exercise two live PencilKit canvases with uncaptured ink, save failures, an actual PDF import/restore/export, restored editable strokes, source-note references, native picker completion/cancellation, dismissed-preview cleanup and light/dark/accessibility layouts.

On a physical iPad:

1. Write in two open notebooks, add an image and review a linked study card. Create a backup immediately after the last stroke.
2. Save through Files to an external location; cancel a second export and confirm there is no success message for it.
3. Restore the saved archive. Confirm existing notebooks remain, restored copies have independent files, PDF/image content appears, both strokes remain editable, and Study opens the corresponding restored source page.
4. Check restored folders, sections, page order, favorites, Trash and review history; relaunch offline.
5. Dismiss the preview without restoring. Select a damaged archive and confirm a visible error with no added records.
6. Repeat with a large real library while checking free space, responsiveness and export provider behavior. Simulator fixtures do not establish physical Pencil latency or third-party file-provider reliability.

## Captured flashcards and compatibility

Manifest record version 2 adds optional question/answer image paths to card records. The container layout and magic remain unchanged. Required-image validation, all-files capture, additive UUID remapping and restored asset namespace rewriting cover these images too. Version-1 archives remain readable and restore plain cards with nil images. Version 2 is rejected by older applications that support only record version 1, preventing an apparently complete restore that silently drops image faces. This format change is separate from SwiftData schema V7.


## Recoverable pages — November 26, 2026

Manifest version 3 adds optional SavedPage.trashedAt. Capture includes active and removed pages with all files, and restore retains removal state and remaps card sources together. The preview reports removed-page counts. Versions 1 and 2 decode with nil removal timestamps. Older apps reject v3 rather than silently resurrecting removed pages. The binary container and magic remain unchanged. See [DataRecovery.md](DataRecovery.md) for migration, UX and physical acceptance; Settings now contains an offline recovery guide.
