# Account-scoped local sync state

Implemented November 25, 2026. This is passive persistence/recovery infrastructure. No CKContainer, account lookup, engine instance, opt-in UI, notification registration or network operation is started. AppDependencies does not create this store at launch. The user library remains on schema V8, with automatic SwiftData CloudKit integration disabled. No user-store migration, entitlement or document-path change is introduced.

## Separate store and identity

SyncStateStore owns a separate versioned SwiftData SQLite store at Application Support/HeyNotesSyncState/State.sqlite. SyncStateSchemaV1 contains Library, Record and Receipt; its own migration plan starts at version 1. These models are not part of NotesSchemaV8 and never enter portable editable backups. The owned directory is excluded from system backup. The store reports errors without an automatic reset or deletion/recreation fallback.

SyncStateDirectory rejects symlinked paths and nonregular SQLite/lock files and holds an exclusive nonblocking flock for one active writer, including across instances/processes. close() revokes the service instance and releases that lock; old queued operations fail. Idle SQLite connections can remain retained until their container deinitializes, but closed services cannot write through their methods. Other code must not bypass the service by writing its model container directly.

registerLibrary(named:) returns a durable local installation UUID for an explicit logical key such as primary. It is an identity for this sidecar registration, **not a fingerprint embedded in the user SQLite store**. Future activation must pair it with the correct user ModelContainer and define policy for restored/replaced stores or a missing sidecar. Losing an excluded sidecar must not silently authorize uploading a restored library to a different account. Initial enrollment and account-aware restore remain separate gates.

SyncAccountScope includes the container identifier, development/production environment, actual authenticated account record name, custom zone name and zone owner. A SHA-256 key uses length-delimited values. Raw account names do not appear in keys or directory names, although the scope is intentionally stored inside the app-private database for ownership verification. CKCurrentUserDefaultName is rejected as an account identity: the same placeholder cannot distinguish people. The future adapter must obtain and verify the real current account before binding; these local APIs do not authenticate it.

## Binding and callback lifetime

bind(scope:libraryID:) explicitly enrolls an unowned registration or resumes the same scope and returns a SyncStateLease. Every resumption issues a new generation. A different account, container, environment or zone is rejected for an already-owned registration; there is no automatic account transfer or reset. Separate registered libraries have separate record/receipt namespaces even when their cloud scope is identical.

pause(libraryID:) invalidates active callbacks while retaining the owner, system fields, checkpoint and receipts. Reopening a service also invalidates old leases through an instance generation. Every state read/write validates the registration, scope and lease. During receipt replay, bind/pause/close report busy rather than changing ownership halfway through a journal transaction. A future account-change handler must stop transport, quiesce recovery and retry pausing; no account listener is implemented here.

Record metadata uses an expected-version compare before replacement. A callback based on older locally stored metadata fails instead of overwriting a newer version. The sender must serialize/reconcile conflicting operations per record; this check is conservative bookkeeping, not an ink or server-conflict resolver. Secure system-field decoding verifies record ID, zone and type. Corrupt record scope/name/type mappings fail and are retained.

## Confirmation recovery across two stores

The sidecar and the user's SwiftData database do **not** share an atomic transaction. Recovery uses this order:

1. After a trusted successful send event, call storeRecord with the actual returned record, the expected stored version and the captured SyncSentRevision. Validate entity kind/UUID, local revision, operation and zone. Commit system fields plus a receipt in one sidecar transaction.
2. replayReceipts invokes SyncAcknowledgementStore using its own fresh context on the corresponding user ModelContainer. It conditionally removes only a SyncChange with the exact sent UUID revision and commits the journal transaction. It does not save or roll back the editor's context.
3. Only after that save succeeds, remove those receipts in a separate sidecar transaction. Each replay processes at most 100 receipts; keep draining before engine restoration.

If the process stops between steps 1 and 2, the receipt survives. If it stops between steps 2 and 3, replaying a missing journal row is a no-op. An intervening newer revision remains pending. Failed journal saves preserve the receipt and metadata. Failed sidecar confirmation saves roll back both fields and receipt. A confirmation ID is idempotent while its receipt is retained; after cleanup, old callbacks are rejected by version checks rather than promising unlimited duplicate-result retention. Source upload packages are not automatically discarded by this service.

All application journal-producing saves now share SyncChangeJournal.withSaveBoundary with acknowledgement check/delete/save. This short process-wide recursive lock prevents another in-process commit from replacing revision R1 with R2 between an acknowledgement's conditional fetch and delete commit. There is no await, network work or asset copying inside it. Replay batches are bounded. This is **not** a cross-process lock for the user database: extensions or additional writers must be designed before enabling them. Future nonjournaled remote-apply commits also need an explicitly coordinated save boundary. The sidecar's separate filesystem writer lock serves a different purpose.

storeRecord must never be called with a sent revision merely because local CKRecords were prepared. It is a trusted transport-event API, not proof of a server response. Tests supply synthetic response values explicitly; no UI reports them as cloud success. The real delegate must distinguish successful records from failed/conflicting/partial results before creating confirmations.

## CKSyncEngine checkpoints

engineState and saveEngineState use the actual public CKSyncEngine.State.Serialization Codable type. They restore nil for a genuinely absent first checkpoint. Corrupt bytes report damaged state and are retained; they do not become a fresh empty engine. Serialization is capped at 8 MiB. A caller-assigned increasing sequence, captured in delegate event order before suspension, rejects reversed checkpoint completions within a lease. Rebinding resets that event counter for the new engine session while retaining its previous serialized bytes.

Both checkpoint read/write APIs refuse to advance while receipts need recovery. The future delegate must also commit all fetched user data and its import/recovery journal **before** saving the corresponding stateUpdate event. Incoming apply is not implemented, so outgoing receipt protection alone is not a complete checkpoint/import protocol.

There is deliberately no fake engine or fabricated Apple serialization fixture. The typed checkpoint adapter compiles against the installed SDK; absent-state and damaged-byte paths are tested. A successful round trip of a nonempty serialization emitted by a real CKSyncEngine, reversed real stateUpdate events, real server change tags and actual account events require the configured-container milestone. No such runtime validation is claimed yet.

Construct these services on a background coordinator executor when activation is implemented; container opening is synchronous. Do not construct/reopen the sidecar in a stroke handler, SwiftUI body or tab-switch render. Normal document editing currently does not instantiate or call it.

## Verification

All **88 host tests passed** (86 Swift Testing plus two XCTest metadata cases). Eight new cases cover disk reopening/registration identity, account/container/environment/zone/library isolation, paused/obsolete leases, stored system-field reuse, durable receipt recovery on both sides of journal commit, newer revisions, idempotent retained confirmations, compare/version rejection, injected save failures and independent editor changes, actual concurrent background journal commits, corrupt checkpoint/scope metadata and exclusive-writer/symlink rejection.

The concurrency fixture runs acknowledgement and an independent writer against the same real user SQLite store, asserts their critical-section event order and verifies the newer intent remains. Its early version depended on MainActor resumption to release a deliberately blocked save; parallel tests could block that actor and time out. The final fixture releases from an independent dispatch worker, without adding production hooks or changing recovery policy for the test.

All **21 selected native tests** and the signed Release build pass. The two-editor integration test persists a synthetic old-revision confirmation in the sidecar, reopens it, replays it and verifies the newer PencilKit drawing, both canvas identities, pending revision and secure system fields survive. These are local persistence/integrity tests, not a real upload or physical-device account test. See Validation.md for logs and scope. The verified implementation, tests and documentation were subsequently organized into scoped local commits at the owner's request. No installation or push was performed.

## Next milestones

1. Initial enrollment/reconciliation of an existing library, explicit opt-in, sidecar/user-store pairing and account-aware restore/switch policy. The existing outbox only covers changes since its migration; it is not a complete initial upload inventory.
2. Confirm final bundle/team identity and create/configure the development CloudKit container. Add the real CKSyncEngine adapter with verified account events, durable stateUpdate handling, success-only confirmations and serial per-record retries.
3. Implement incoming staging/apply recovery and editable conflict copies, then trial one notebook on two physical devices through offline edits, termination and sign-out/sign-in. Verify genuine nonempty engine serialization and server change tags.

The offline-v1-first product decision and future production-schema/TestFlight gates remain unchanged. Large-asset chunking and the current 40 MB cloud-preparation cap remain separate from this state-store milestone.

Apple references: [persisting stateUpdate events](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/event/stateupdate), [Serialization](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/state-swift.class/serialization), [initial stateSerialization](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/configuration/stateserialization), [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor).
