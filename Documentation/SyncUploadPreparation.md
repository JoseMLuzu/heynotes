# Immutable local upload preparation

This is a local CloudKit preparation milestone, not active synchronization. No container, account access, engine, remote records or cloud-success UI is enabled. The owner confirmed that no iCloud container has been created yet. V8 remains the current metadata schema; this milestone adds no model fields or migration stages.

## Capture boundary

`DocumentWorkspace.prepareSyncUpload(_:staging:)` first calls `captureSyncUpload(_:)` inside the existing `withSavedLibrary` boundary. Both visible editors must be idle enough to navigate, then flush their actual native canvases and pending metadata. Busy input and failed ink saves reject preparation. The metadata actor reads the pending record and user entity into private Codable values, using a fresh context to avoid stale registered objects.

While that boundary is still held, `DrawingStorage.captureSyncSources(_:)` opens read-only descriptors for all referenced files. It checks the app-relative paths, rejects symlinks/nonregular files and retains the current inodes. Only an unrecorded blank page's absent deterministic drawing file is optional; missing explicitly referenced drawings, PDFs, images or imported font assets fail visibly. Malformed inserted-object envelopes also fail. Deletion plans contain no user payload or files.

After descriptor capture returns, the workspace resumes editing. Streaming and hashing then run on the separate staging actor, outside both the main actor and DrawingStorage's serialized write executor. DrawingStorage's existing atomic replacement writes cannot change the captured inodes, and source removal cannot invalidate a retained descriptor. Unsupported in-place source mutation is detected by size/mtime checks and short reads.

`SyncSourceFile` is an immutable descriptor owner with narrowly justified unchecked Sendable conformance: copies use `pread` with independent offsets and only descriptor deinitialization closes it. This supports concurrent copies without sharing a seek cursor. Capture must always use the successful workspace boundary; calling file capture against unflushed live editors is not a supported preparation path.

## Prepared package

The default root is `Application Support/HeyNotesSyncUploads`, outside the document storage and excluded from system backup. Each package has its own UUID directory and contains:

- `manifest.json`: version, entity kind/UUID, local revision, operation and asset-role hashes/sizes.
- `metadata.json` for upserts: a private local value snapshot with an integrity hash.
- SHA-256-named `.asset` files; roles with identical bytes share one file within the package.
- A small ownership marker used before explicit deletion.

Package and asset identifiers do not depend on notebook titles, page positions or device-specific paths. Absolute URLs are not serialized. The private metadata snapshot reuses the editable-backup value mapping and can contain **relative local paths**; it is not a finished CloudKit record payload. The separate [local wire mapper](SyncCloudRecords.md) now replaces those references with blob record IDs in a versioned derived payload. Original local metadata is retained unchanged; neither format is sent automatically.

Copies use 1 MiB chunks, keeping PDF/drawing streaming buffers bounded. Current explicit limits are 256 file roles and 64 MiB of encoded metadata per item, with a 1 MiB manifest-read limit. These bounds do not make metadata encoding constant-memory. Shared PDF hashes remain stable across packages, but cross-package storage sharing and server-side upload deduplication are not implemented.

Preparation writes into an owned `.building-<UUID>` directory, checks cancellation, closes/synchronizes copied files and publishes the complete directory by rename. Package payload/manifest files are read-only. Failed preparations remove only their own unpublished directory. There is no claim of a transaction shared with SwiftData or of hardware power-loss testing.

## Retry, integrity and lifetime

`packageIDs()` lists completed UUID names. `load(_:)` checks format, identity, operation, safe paths, byte counts and SHA-256 hashes before reusing a package. Unsupported, damaged or symlinked content is reported and retained rather than silently removed. Incomplete `.building-*` directories left by process termination are not listed as ready and are retained for later explicit recovery/housekeeping policy.

`PreparedSyncUpload.cloudAssets()` constructs actual public `CKAsset(fileURL:)` objects pointing only at prepared asset files. It does not open a CKContainer or contact a database. Role keys are local names, not a CloudKit schema. Apple does not remove the caller's original upload files after saving an asset; the app must manage that lifetime. See [CKAsset initialization](https://developer.apple.com/documentation/cloudkit/ckasset/init(fileurl:)).

A future sender must retain the package until its CloudKit operation has finished. There is no automatic pruning or acknowledgement on preparation. `discard(_:)` requires a UUID below the owned root and its ownership marker; it never accepts an arbitrary URL or removes original document files. Discarding one package cannot remove a newer package's copies.

If editing creates revision R2 while the package for R1 is being copied/sent, R1 retains its captured metadata and bytes. Conditional journal acknowledgement of R1 cannot clear R2. Future transport still needs version-aware batch selection, server change tags, account binding and conflict policy; a prepared package alone does not solve ordering or ink conflicts.

## Verification

Host coverage exercises source replacement/removal after capture, reuse after recreating the staging actor, shared-image deduplication, concurrent multi-megabyte copies, metadata freshness, stale acknowledgements, missing/unsafe/symlinked paths, source mutation, cancellation, damaged packages, explicit cleanup, partial directories, card images and deletion plans. Existing backup round-trip and migration tests use the same extracted value mapping.

Native coverage captures two live PencilKit editors, including ink whose final delegate callback has not fired; resumes editing before copying; saves a newer drawing; verifies that the prepared drawing remains editable and retains the older stroke count; opens the captured PDF with PDFKit; and verifies actual CKAsset file URLs. Busy-input and failed-save cases preserve pending ink and create no package. See [Validation.md](Validation.md) for exact results and the separate pre-existing full-suite UI failures.

## Next gate

The wire mapper and secure system-field codec are implemented locally; see [SyncCloudRecords.md](SyncCloudRecords.md). Account-scoped system metadata/receipt recovery and typed engine checkpoint persistence now exist in a separate passive sidecar; see [SyncStatePersistence.md](SyncStatePersistence.md). Next define initial enrollment, explicit opt-in and account-aware restore/switching. Actual transport requires the development CloudKit container using the final app identity/team, real engine/account verification and a one-notebook two-device trial. Remote apply, editable conflict copies and production rollout remain separate gates. The app continues to work offline.
