# Durable incoming reception

Implemented November 26, 2026. This milestone receives and verifies local representations of fetched changes. It does not connect to an account, run CKSyncEngine, modify the user library, apply conflicts or authorize a checkpoint/acknowledgement.

## Components

- SyncIncomingInput(fetched:scope:) is the actual public-SDK boundary for CKRecord and CKAsset. It requires the configured zone, a supported server header and a real recordChangeTag; locally prepared proposals are rejected. It pins regular-file descriptors for asset bytes. SyncIncomingStore.receive(fetched:deletions:deliveryID:) also checks the zone/type of real SDK deletion values.
- SyncIncomingRecord/Manifest describe normalized records, hard-deletion notices and library/scope ownership. Persistent manifests contain generated relative filenames and blob names, never temporary CKAsset URLs or permanent absolute paths.
- SyncIncomingPayloadValidation checks wire-v1 identity/revision, metadata types, finite dimensions/dates/intervals, page/PDF fields, unique asset roles, hashes, declared blob sets and exact metadata-to-role references. It supports all seven entity kinds, including captured-card images and V9 page removal state. It rejects local paths in file-valued wire fields.
- SyncIncomingFiles handles bounded, checksum-wrapped metadata, read-only asset copies, atomic publication and file/directory synchronization. SyncSourceFile now exposes bounded reads/fingerprints through its already pinned descriptor, sharing the existing pread streaming path with upload copies.
- SyncIncomingStore owns a separate App Support inbox, exclusive writer lock and durable library/account binding. Reopening with another library, account, container, environment or zone is rejected; data is not reset. It reuses the existing directory-lock primitive, without creating a SQLite store or changing either SwiftData schema.

Apple notes that downloaded CKAsset files reside in a reclaimable staging area; copy them into app-owned storage promptly. See [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset). No asset URL is treated as durable remote content.

## Commit and recovery boundaries

1. Validate the nonempty delivery and its unique record/deletion names before creating its directory. An ambiguous modification and hard deletion of the same record are rejected.
2. Persist a checksum-wrapped manifest under receiving-<delivery UUID>, flush the manifest, its directory and the parent directory. The caller supplies the delivery UUID and must retain it for an explicit retry.
3. Stream asset bytes in 1 MiB chunks into private partial files, check expected size/SHA-256, synchronize and publish each immutable generated filename. Unsupported in-place source mutation fails. Atomic replacement/deletion of the old temporary path cannot redirect a pinned read.
4. Reverify the entire delivery, including each entity's wire payload. Rename the receiving directory to the UUID and synchronize its parent. Only then return SyncIncomingReceipt, which means **durably received**, not applied or synchronized.

A failure after rename can leave a complete published delivery even though its caller received an error. Reopen and resume/load the same UUID to verify it; do not assume nothing happened. Reusing the UUID with a different manifest is rejected. Reordered input records and a different client receive timestamp do not defeat an otherwise identical retry. This UUID is not a global server change identifier: independently redelivered events with a new UUID are retained separately for future revision-aware reconciliation.

inventory distinguishes published and interrupted directories. resume verifies all previously copied bytes and can publish a complete interrupted delivery without the original temporary downloads. A missing file reports incomplete; a corrupt file/manifest reports verification failure. Neither creates a ready placeholder nor deletes the files. receive can fill a valid interrupted manifest on retry. A directory whose manifest never finished, corrupt intent or partial files remain retained for explicit later repair/refetch/cleanup. No automatic purge or crash-proof power-loss guarantee is claimed; tests simulate exceptions at durable boundaries rather than terminating hardware.

The owner binding and manifests have SHA-256 integrity wrappers. Hashes detect accidental corruption; they do not authenticate a cloud account or resist an attacker with write access to the whole app container. The future transport must verify the actual account and valid lease before/after asynchronous work. This local store trusts its supplied scope and never queries an account.

## Complete delivery versus complete entity

CloudKit can deliver metadata before its blobs. A complete delivery may therefore be durably retained while a referenced entity remains unresolved. entity(name:in:) verifies the requested delivery and resolves its blob roles only from published deliveries in the same bound inbox. Missing dependencies raise missingAsset; there is no empty page replacement. Identical hashes can serve multiple roles; each referenced copy is reverified before use. Asset URLs returned by this method are transient read-only inbox locations; an importer must copy them to independently writable app-relative paths.

Hard deletions and entity tombstones remain queued descriptions. No notebook/page/file is deleted, no newer local pending revision is acknowledged, and no remote revision is selected as the winner. UUID-sorted inventory and client receivedAt dates are not server ordering. Resolving a historical delivery says nothing about the latest server version. Parent availability, notebook/section graphs, account changes, deletion conflicts and semantic validity of PKDrawing/PDF/image/font content must be checked before a later apply transaction. Positive native fixtures demonstrate readable real ink/PDF; byte integrity alone does not establish semantic readability of arbitrary received content.

Raw CloudKit system-field archives and engine tokens are not stored by this inbox. The existing account-scoped state store remains their separate owner. The future delegate must coordinate verified incoming receipts, trusted fetched-record metadata and checkpoint order; it must not advance state after a failed reception. No delegate/checkpoint integration is enabled in this milestone.

## Explicit first-version bounds

- At most 200 modifications/deletions per delivery; at most 256 roles in one payload.
- At most 40,000,000 bytes per file and 200,000,000 unique file bytes per delivery. These are product preflight bounds, not statements about current CloudKit server limits.
- At most 2 MiB for a checksum-wrapped persistent manifest and 10,000 retained delivery directories. There is no automatic cleanup when full; a future explicit recovery/retention policy is required.
- File copies/hashing are streamed on the incoming actor, outside the UI and drawing-write executors. Payload JSON/Data is materialized within its file-size limit; directory enumeration returns an array. This is bounded per-delivery validation, not constant-memory performance acceptance for an unlimited library.
- The inbox is device-local, excluded from system backup by the shared directory helper and outside the portable user-library backup. It is pending transport state, not a replacement for editable library backups.

## Validation and next step

Host coverage uses explicit normalized offline fixtures created from actual local wire packages; it never manufactures a server tag/token inside CKRecord. The actual SDK boundary has a negative test rejecting local proposals. Genuine server-tag decoding and downloaded CKAsset lifetimes require the configured-account acceptance gate later.

The next local milestone is a recoverable import transaction for a single notebook: verify native file readability, resolve all parents/assets, compare pending local revisions and trusted remote metadata, coordinate both live editor sessions, preserve conflicts, and record durable apply progress before considering a receipt consumed. Only after that, connect the real engine on an enrolled/provisioned development account and verify a two-device round trip. Notebook sync stays disabled, and the existing offline privacy statements remain accurate.
