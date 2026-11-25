# CloudKit preparation and proposed milestones

Product decision — November 14, 2026: **ship v1.0 offline and add iCloud after launch**. The sync milestones below are post-launch work and do not block the initial App Store release. See [ReleaseReadiness.md](ReleaseReadiness.md) for the launch critical path.

Status: editable backups are implemented and integrated into `main`. The transactional local change journal, immutable local upload packages, local CloudKit record mapping and passive account-scoped state/receipt recovery are implemented. There are no cloud entitlements, configured containers, automatic uploads or cloud-status indicators. See [SyncCloudRecords.md](SyncCloudRecords.md) for the wire format and [SyncStatePersistence.md](SyncStatePersistence.md) for the new local sidecar and its runtime-verification limits.

## Implemented local change journal — V7 → V8 migration

The shipped V7 user-data layout, including image flashcards, is frozen in `SchemaV7.swift`. V8 retains those seven entity layouts and adds only the local `SyncChange` entity, using a lightweight V7 → V8 migration. V1–V6 snapshots are unchanged. Disk migration tests cover the previously installed global V7 model layout, image faces, source-note references and unchanged asset bytes, alongside the existing older-version migration coverage.

Explicit application metadata saves record pending upserts/deletion tombstones in the same SwiftData context/save as the mutation. Repeated edits coalesce by stable entity kind/UUID. Each pending change gets a fresh revision token, allowing a future transport to acknowledge only the version it actually sent. Cascade deletions retain child identities before saving; nullify deletions also enqueue surviving children/notebooks/pages whose parent or section reference is removed. Failed saves/rollbacks must not commit a separate journal transaction.

This milestone records changes after migration; enrolling the entire pre-existing library is a separate activation/reconciliation step. The journal itself does not implement CloudKit transfer, account binding, server change tags, conflict copies, remote apply or scheduling reconciliation. Immutable local upload snapshots are now implemented as the next separate milestone; see [SyncUploadPreparation.md](SyncUploadPreparation.md). No future sender may treat the journal alone as a complete initial upload or a drawing-byte snapshot. Backups contain user content, not device-local journal state. Restores retain the existing collision-aware identity mapping and their actual inserted IDs are journaled. An account-aware restore policy remains necessary before enabling uploads; locally absent IDs can still exist on a remote account.

## Current constraints

HeyNotes uses a versioned local SwiftData store plus independently stored PencilKit drawings, immutable PDFs and images. Metadata references app-relative file paths; optional stable UUID references connect Study with source notes. Local saves and both visible editors must remain usable without connectivity or an iCloud account.

Turning on automatic SwiftData CloudKit synchronization alone would not synchronize these document files. The current schema also uses unique attributes and nonoptional relationship arrays. Apple's automatic SwiftData/CloudKit integration does not support unique constraints and requires optional relationships. Existing stores and frozen migration schemas must not be rewritten simply to switch a flag.

The proposed approach is an explicit adapter using **CKSyncEngine**, available from iPadOS 17, with a private custom record zone and `CKAsset` for file payloads. This preserves local model invariants and offers explicit per-page conflict/recovery behavior, at the cost of implementing durable sync bookkeeping. It requires a separate technical spike before adoption, not an empty abstraction added to the current app.

## Milestones and gates

| Milestone | Work | Acceptance gate |
| --- | --- | --- |
| 1. Local recovery | Complete library export, integrity validation, additive restore, source-link remapping | Reopen restored stores; preserve editable ink, originals and Study; failed restore cannot overwrite local notes |
| 2. Sync design and migration | V7 → V8 journal, immutable staging, versioned record/blob mapping, separate state schema and account-bound receipt recovery implemented; initial enrollment, real engine/account integration and conflicts pending | Reopen pre-sync libraries without changing IDs, paths or content; local-only mode remains fully functional |
| 3. One notebook | Explicit opt-in; notebook/page records plus drawing assets; foreground receive/apply and retry | Two physical devices round-trip one real notebook offline/online, across process termination and account changes |
| 4. Full document content | Folders, sections, PDFs, images, margins, bookmarks, moves, ordering and Trash | Large/mixed libraries retain geometry and assets; document moves never re-upload identical binary content unnecessarily |
| 5. Study and release hardening | Decks/cards/reviews, reference resolution, conflict diagnostics and status UI | Concurrent reviews do not lose history; stable links survive conflicts/restores; production schema and TestFlight migration verified |

Each gate leaves a usable build. Do not present a local save dot as cloud success before the server has confirmed the corresponding revision.

## Record and asset design: implemented foundations and remaining work

- Implemented locally: model-type-plus-permanent-UUID entity names, stable relationship IDs, content-addressed blob names and a versioned payload. Partial-download resolution must still avoid editable empty replacement pages or removal of existing ones.
- Implemented locally: structural file paths are replaced with blob IDs before creating CKRecords. Immutable upload files remain present until explicit discard. A future sender must retain them through operation completion and implement cross-package/server upload deduplication.
- Record each committed local change durably in an outbox. Persist CKSyncEngine serialized state and successful server record system fields/change tags. Handle crashes between SwiftData, outbox and filesystem updates with an explicit import/recovery journal and idempotent operations.
- Store per-page revisions and an agreed base revision. Two-device drawing conflicts must preserve both editable drawings in a recoverable conflict copy; merging `PKDrawing` bytes by timestamp is unsafe. Use deterministic policies for metadata conflicts, section/page ordering and folder-parent cycles.
- Treat deleted/trashed items separately. Use durable tombstones and retention rules before any remote hard delete; propagate references in a recoverable order. Do not allow an old offline device to resurrect or purge notes unintentionally.
- Keep review records as append-only events with stable IDs. Derive/reconcile scheduling state using an explicit versioned policy rather than letting conflicting counters discard one device's review.
- Coordinate remote apply with both live editor sessions. Finish pending local ink before importing a competing revision; refresh or defer background updates instead of replacing the active canvas during a stroke.
- Define opt-in, account unavailable/sign-out/account-switch behavior. Never silently clear the local library on an account event. Avoid uploading one account's local library into another account automatically.

## Configuration and verification prerequisites

Local preparation can continue with initial enrollment, explicit opt-in, user-store/sidecar pairing and account-aware restore policy. The passive sidecar now persists system fields, receipts and typed engine checkpoints; real nonempty engine serialization and account events remain untested until a container is configured. Actual transport needs the Apple Developer team/container configuration and development CloudKit environment. Enable only the required capabilities, then validate signing, private database access, notifications, retries and offline operation on two devices. Development and production schemas remain separate deployment steps.

Before enabling sync on existing user libraries: save a backup outside the app, test the migration against a frozen V7 fixture, exercise missing/corrupt assets and full disk, test retry/duplicate delivery, kill during upload/download/commit, conflict both handwriting and page order, restore a backup while sync is enabled, and change iCloud accounts. Collision remapping creates new IDs for colliding local records. Before enabling sync, define account-aware handling for restored IDs that are absent locally but may exist remotely; do not blindly overwrite remote content.

## Apple references

- [Syncing SwiftData model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [Synchronize with the CloudKit sync engine — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10188/)
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
- [Exporting with the native document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:))


## Transaction boundaries and current limits

`ModelContext.saveRecordingSyncChanges()` stages intents and user metadata in the same context, then performs one save. Library/PDF operations, debounced ink checkpoints, inserted objects/bookmarks, Study/sample decks, backup restore and workspace/background flush boundaries use it. `SyncChangeJournal` ignores its own entity changes, coalesces by kind plus permanent UUID, bounds fetch predicates to 100 keys, and stages acknowledgements only when the revision token still matches. It performs no networking and does not add a second drawing save or a per-movement task.

A journal row is an intent to reconcile the latest committed local entity, not a historical payload. It does not snapshot file bytes, contain CloudKit system fields/account tokens or establish a base for concurrent ink merging. Metadata and files still have independent atomic boundaries. Immutable staging, wire mapping and separate account-bound state/receipt recovery are implemented. Before starting a sender, implement initial reconciliation, verified account/engine integration, incoming recovery and editable conflict handling. Future remote imports must deliberately choose whether to journal and coordinate their commits with the save boundary; the normal application save helper represents local edits.

A clean migrated library initially has no pending rows until a local save changes an entity. Creating the complete initial upload is an explicit future activation step. The local blue/orange save dot continues to represent saving on this iPad only. No iCloud switch, success message or automatic account access is exposed in this milestone.


## Immutable upload packages implemented

`DocumentWorkspace.prepareSyncUpload` flushes both editors and captures metadata plus read-only source descriptors inside a short quiescent boundary, then releases editing before chunked copying/SHA-256 work. Prepared copies are atomically published into owned Application Support directories, survive reopening and are verified before retry. Actual CKAsset objects point at the copies, never live document paths. Preparation does not acknowledge a journal entry, upload a record or delete source files. Native tests exercise newer PencilKit saves while an older captured drawing/PDF revision is prepared.

The owner confirmed that no iCloud container exists yet. Creating one and verifying the final app identity/team remain prerequisites for actual CloudKit configuration. No placeholder container identifier or signing capability has been added. See [SyncUploadPreparation.md](SyncUploadPreparation.md) for file lifetime, limits, retry/cancellation behavior and remaining transport gates.

## Local wire mapping implemented — November 24, 2026

Verified packages can now produce real CKRecord values with immutable CKAsset payloads and shared blob identities. All seven metadata entity kinds are covered; nested object image/font paths and card images are transformed along with drawing/PDF references. Permanent deletion intents become tombstones with no hard-delete or shared-file cleanup. A secure system-fields codec validates record identity/type/zone for future server metadata reuse, but does not persist engine/account state. No account or database is contacted. See [SyncCloudRecords.md](SyncCloudRecords.md) for the schema, receiver requirements, conservative 40 MB preparation cap, verification and next steps.

## Passive account state implemented — November 25, 2026

SyncStateStore adds a separate versioned local SQLite sidecar, stable registration IDs, explicit scope ownership, revocable leases, system-field versions and durable success-receipt replay. Receipt replay cannot clear a newer outbox revision or save/roll back the editor context. Journal-producing commits and conditional acknowledgement commits now share a short in-process boundary. CKSyncEngine serialization has typed persistence APIs, but a genuine nonempty engine checkpoint still needs configured-container testing. No engine, account access or automatic enrollment runs at startup. See [SyncStatePersistence.md](SyncStatePersistence.md) for limitations and the next activation gates.
