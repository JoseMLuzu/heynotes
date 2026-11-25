# Local CloudKit record preparation

Implemented November 24, 2026. This milestone converts verified local upload packages into actual CKRecord/CKAsset values without constructing a CKContainer, checking an account, creating a zone or making network requests. The app remains offline-first with SwiftData CloudKit integration explicitly disabled. There are no new entitlements, sync controls, cloud-success indicators or user-store schema changes; V8 is unchanged.

## Preparation boundary

1. Use DocumentWorkspace.prepareSyncUpload after the existing successful two-editor flush/capture boundary. The immutable package retains its captured local revision and file bytes while editing resumes.
2. Call SyncUploadStagingStore.cloudRecordPlan(packageID, zone:systemFields:). The caller supplies an explicit custom zone ID; constructing it does not create a server zone. The default zone is rejected. No real container or zone is configured by this milestone.
3. The staging actor reopens and verifies the original manifest, metadata and file hashes. It decodes copied metadata off the main actor, checks the entity ID, replaces structural file references with blob IDs and rejects missing or unexpected file roles.
4. For an upsert it atomically writes a read-only cloud-v1-SHA256.json payload beside the owned package. A retry derives the same filename and verifies an existing payload rather than silently replacing damaged content. Restarting the staging actor reuses the original package. The derived file is an owned, reproducible artifact; it is not part of the original upload-manifest integrity envelope and is verified separately when rebuilding a plan.
5. Return a SyncCloudRecordPlan containing the entity and unique content blobs. No journal acknowledgement, save scheduling, source-file deletion or transport operation occurs. Retain the package until all future operations using its assets finish. Explicit package discard remains the existing owned-directory operation.

If preparation fails or is cancelled, original notes and pending revisions remain. A complete derived payload can remain after a later record-metadata validation failure; it is harmless and reusable. Incomplete process-termination recovery and power-loss durability are not newly claimed by this milestone.

## Proposed development record schema

These names define the current local format. There is no deployed CloudKit schema yet. Record types remain fixed for their identities; future compatible format changes use explicit schema/payload versions rather than assuming a record's type can be changed in place.

| Type | Record name | Fields |
| --- | --- | --- |
| HNEntityV1 | Existing entity-kind.permanent-UUID, lowercased | hnSchema (Int64, 1), hnKind (String), hnRevision (String UUID), hnDeleted (Int64, 0/1), hnPayload (Asset), hnPayloadHash (String), hnBlobs (String list) |
| HNBlobV1 | blob.lowercase-SHA256 | hnSchema (Int64, 1), hnHash (String), hnBytes (Int64), hnAsset (Asset) |

All records use the caller's custom zone. Names never contain titles, page positions, local paths or SwiftData implementation identifiers. Blob names are scoped by that zone; they are not a global cross-account cache. Multiple roles with identical bytes share one blob in a plan. Stable blob IDs also remain identical across packages, but server-side existence checks, upload skipping, batching and reference-aware garbage collection are **not implemented**. A future sender must save blobs before their entity or use a suitable atomic batch, respect service batch limits and retain dependencies during partial retries.

The entity's payload is an asset even when its JSON is small. Large recovery-ink metadata therefore does not occupy an inline CKRecord Data field. The header contains only small scalar/list fields. Apple's current CKRecord documentation places a 1 MB limit on non-asset record data; this design does not place the full metadata inside that limit.

### Payload version 1

SyncCloudPayload contains version, permanent identity, captured revision, metadata and an ordered assets list. Each asset binding contains its role, blob record name, SHA-256 and byte count. Metadata currently uses the seven explicit saved-value layouts already shared with local capture: folder, notebook, section, page, deck, card and review. The wire envelope has its own version; it is not a portable backup or an incoming-import API.

Page drawing/pdf fields, inserted objects' imagePath/fontFilePath and card questionImage/answerImage fields contain **blob record names instead of local file paths** in this wire format. The nested inserted-content envelope is decoded, transformed and reencoded too; source ink, its anchors, fonts, geometry, margins, dates, ordering and user text remain unchanged. This transformation affects temporary values only. Ordinary user text is not filtered merely because it contains a path-like string. Source notebook/page IDs and append-only review IDs/history are preserved.

A receiver must resolve these foreign keys through the asset bindings, download and verify all required assets, assign safe local relative paths and validate the complete result before installing local models. Do not pass wire metadata directly to BackupMetadataRestore, rendering or DrawingStorage as if its blob names were local paths. Missing downloads must not produce editable empty replacement pages. Remote apply and its recovery journal remain future work.

### Deletion and server metadata

A pending local deletion produces an entity **tombstone record**, not a hard delete. It sets hnDeleted to 1 and explicitly clears payload/hash/blob fields, including changed-key tracking when using restored system metadata. No blob is deleted; another page/card may share its PDF, image or font. Trash remains ordinary metadata in live entity payloads, distinct from a permanent local deletion. Old-revision resurrection, retention, conflict resolution and eventual remote cleanup still require a transport policy; a tombstone alone does not settle concurrent edits.

SyncRecordSystemFields securely encodes only CKRecord's system fields and reconstructs a record only when its ID, zone and record type match and it has no user fields. Supplied metadata can preserve a future server change tag instead of reconstructing an existing record as new. Corrupt/mismatched archives fail. Tests exercise locally constructed records, not server-generated change tags. The codec itself does not provide persistence; the subsequent [account-scoped sidecar milestone](SyncStatePersistence.md) now stores system fields, receipts and typed engine checkpoint data. No real engine is started and genuine nonempty engine serialization still requires configured-container testing.

## Current limits and remaining gates

- Cloud preparation uses a conservative **40,000,000-byte product limit per binary or generated payload asset**, checked locally. This is not a statement of CloudKit's server limits. Larger files/packages are retained and reported, not truncated or acknowledged. Chunked large-PDF transfer is future work. The pre-existing staging limits remain separate.
- Hashing uses the existing streaming worker; JSON encoding/decoding still allocates bounded whole metadata values. This is not constant-memory encoding or an app-wide RAM cap. The new conversion runs on the staging actor and is not called by the live stroke handler.
- Passive checkpoint persistence and initial local enrollment are implemented in the later milestones linked below. Automatic sending, account opt-in, genuine engine/account verification, remote import, editable conflicts, account-aware restore and a two-device round trip remain pending.
- The codec is not a complete validator for downloaded data or graph consistency. Full inbound validation, absent parents, folder cycles, page/section ownership and missing source-note handling must be resolved before remote apply.

The [state-persistence milestone](SyncStatePersistence.md) implements local ownership/receipt recovery; [initial local enrollment](SyncInitialEnrollment.md) now queues pre-journal content safely. Next define explicit opt-in, remote baseline reconciliation and account-aware restore/switching. To enable transport, confirm the final identity/team, create the development container/capabilities, add CKSyncEngine and trial one notebook on two devices. Conflicts, incoming recovery, genuine engine/account verification, large-file policy, production schema and TestFlight remain gates. The offline-v1-first decision is unchanged.

## Verification and public APIs

All 80 host tests (78 Swift Testing plus two XCTest metadata cases), 14 selected native tests and the signed Release build pass. New tests cover all entity kinds, exact scalar/source-link/history preservation, rich metadata above 1 MB as an asset, file-reference replacement, editable recovery bytes, shared blob IDs, restart/retry, newer pending revisions, tombstone clearing, system-field identity checks, damaged data, cancellation and size preflight. The native two-editor test reads actual staged ink with PencilKit and the original PDF with PDFKit while newer local ink remains present. Validation.md records logs, scope and a test-fixture correction.

APIs used here are available below the iPadOS 17 deployment target. Verified with Xcode 27.2 / Swift 6.4.2; simulator execution uses iPadOS 26.5, not a minimum-OS runtime or a real CloudKit account. At the owner's subsequent request, the verified code, tests and documentation were organized into scoped local commits. No device installation or push was performed.

Apple references:

- [CKRecord supported values and record size](https://developer.apple.com/documentation/cloudkit/ckrecord)
- [CKAsset lifetime and file metadata](https://developer.apple.com/documentation/cloudkit/ckasset)
- [System-field encoding](https://developer.apple.com/documentation/cloudkit/ckrecord/encodesystemfields(with:))
- [Custom zone identity](https://developer.apple.com/documentation/cloudkit/ckrecordzone/id)
