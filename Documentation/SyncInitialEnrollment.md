# Initial local library enrollment

Implemented November 25, 2026, after the scoped sync-state commits. This milestone discovers committed content that predates the V8 journal and inserts only its missing local upload intents. It does not access an account, construct an engine, reconcile a server library or authorize uploads. Its final status is deliberately named readyForRemoteReconciliation.

## Migration plan and implementation

The user metadata store remains on NotesSchemaV8, with unchanged entity IDs, relationships, file paths and migration stages. Only the separate app-owned sync sidecar advances from SyncStateSchemaV1 to V2 using a lightweight migration. The V1 model declarations are frozen. V2 replaces its Library model with the same previous fields plus three optional progress fields: enrollmentID, enrollmentStartedAt and enrollmentReport. Unchanged V1 Record and Receipt types remain in V2's model list.

An existing V1 sidecar retains ownership, registration UUIDs, secure system fields, receipts and engine bytes. A migration does not enroll anything automatically. A populated pre-existing engine checkpoint prevents this first-enrollment path and requires explicit existing-state reconciliation; it is not cleared. Migration failure propagates through the existing sidecar initialization error path with no deletion/recreation fallback. No production cloud capability or container setting changes.

## Workspace and transaction boundaries

DocumentWorkspace.prepareInitialSyncEnrollment(state:lease:) uses withSavedLibrary to quiesce both visible editors and flush their actual native canvases and pending metadata. Busy input or failed saves reject the operation before an enrollment marker is created. The source ModelActor is constructed on a detached utility task so its context does not inherit the main executor. The workspace interaction gate is restored on success or error; canvas identities are retained.

The bound sidecar coordinator performs three stages:

1. Validate the active account/library lease and source library ID. Require receipt recovery first and reject a pre-existing engine checkpoint. Commit a durable begin UUID and timestamp before touching the user journal.
2. SyncInitialEnrollmentStore reads committed IDs in its own fresh user-store context and inserts missing SyncChange upserts in **one atomic user-store save**. The shared save boundary covers the inventory and commit, so another participating writer cannot change the enumerated rows midway. Failure/cancellation rolls back only this context.
3. Revalidate the lease and refetch its Library model after suspension, then commit the report in the sidecar. These two SQLite databases do not share a transaction. A durable preparing marker bridges the failure window.

If stage 3 fails after stage 2 committed, retry reuses the begin UUID. All existing journal rows keep their revisions, so it finds the already-seeded intents and creates no duplicates. A completed report makes subsequent calls return the same completion marker without reseeding records whose intents were later acknowledged. Ordinary later edits still create/coalesce intents through the normal save helper. Counters describe the final successful attempt: after a recovered seed they can show zero newly enqueued records and all records already pending.

While preparation is active, binding/pause/close are blocked. A persisted incomplete marker blocks server-result storage, receipt replay and engine-checkpoint access until local preparation resumes. Corrupt completion reports fail closed rather than becoming an empty or completed inventory. Lease changes and wrong source library IDs are rejected. Low-level source.seed is an internal coordinator operation; production callers must use the bound workspace boundary, not rerun it independently.

## Inventory semantics

The source covers all seven committed entity kinds, including items in Trash: folders, notebooks, sections, pages, decks, cards and review events. It fetches only UUID attributes with propertiesToFetch in 256-row batches, then computes counts and a canonical SHA-256 over sorted kind.UUID names. It does not decode inserted-content JSON, read drawing/PDF/image/font files, copy assets, change page positions or edit notebook modification dates. Identity grouping includes entity kind, so a page and notebook with the same UUID remain distinct.

- Existing upserts retain their UUID revision and changedAt date.
- Existing deletion tombstones remain unchanged, including those whose original entity is absent.
- A live entity with a pending deletion, an orphaned upsert, malformed identity or unknown journal operation aborts preparation. The service does not silently repair or resurrect it.
- The combined live-identity and retained-deletion limit is currently 200,000. Exceeding it reports an error and retains original metadata, files and pending rows. This is a local preparation limit, not a CloudKit service limit.
- The result contains point-in-time counts, the enrollment/library UUIDs, completion date, identity digest and final-attempt enqueue/preservation counts. The identity digest is **not a content fingerprint, store pairing proof, source-file integrity check or a remote conflict decision**.

Batching limits each projected fetch, but the live-ID set, pending-row map, inserted intents and sorted digest input still scale with the library. No constant-memory, peak-RAM or hardware latency claim is made. The global save boundary can be longer for explicit enrollment than for normal save/receipt batches; other participating saves wait for it. It never contains an await, network call or asset copy. Large-library chunking and physical profiling remain future work. No scan runs in a SwiftUI body, stroke handler or app startup.

## What remains before upload

A remote account can already contain records whose IDs are absent locally. Empty local content does not imply remote deletion. This service neither sends local content over those records nor infers remote tombstones from absence. Next implement an explicit activation/reconciliation policy: verify the real account, pair the correct user store with its registration, inspect the remote baseline, and preserve/remap conflicts and restored IDs before authorizing sends.

The sidecar registration still is not a fingerprint embedded in the user's store. An externally replaced/restored library or lost sidecar requires account-aware activation policy; a cached completion marker must not be treated as proof that a different database was enrolled. Real account switching, opt-in UI, CKSyncEngine events, incoming apply recovery and editable conflict copies remain separate gates. No cloud-ready boolean or cloud-success UI is added.

## Verification

All **95 host tests** pass (93 Swift Testing plus two XCTest metadata cases). Seven new cases cover a pre-journal library of all kinds including Trash, same UUID across kinds, retained upsert/deletion tokens, unchanged metadata/source bytes, idempotent completion, final-marker failure and restart recovery, seed-save failure, cancellation, inconsistent journal rollback, multiple 256-row batches, empty inventory, V1-to-V2 sidecar migration with retained ownership/metadata/receipts/checkpoint bytes, wrong-library rejection and damaged completion reports. Existing sidecar corruption tests now use V2 for their current-format fixtures; the migration fixture deliberately creates V1 independently.

All **21 selected native tests** and the signed Release build pass. The real two-editor workflow adds an actual pre-journal notebook with editable four-stroke ink, enrolls it through the workspace, verifies exactly its missing notebook/page intents were added and retains source bytes and both existing canvases. Busy and failed native saves leave enrollment notStarted. These are local persistence tests, not live iCloud transfers or physical-device migration acceptance. See Validation.md for logs/results.

The preceding state-persistence milestone was organized into five scoped local commits at the owner's request. The verified enrollment implementation, host/native tests and documentation were subsequently committed separately at the owner's request. No push, installation or active iCloud configuration was performed.

Apple reference: [projected attribute fetches](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/propertiestofetch), available from iPadOS 17. The existing deployment target is unchanged.
