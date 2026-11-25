# Read-only CloudKit activation inspection and review

Implemented after the enrollment commits on November 25, 2026. This milestone provides an actual read-only CloudKit adapter and an advisory comparison with fresh local metadata. It does not enable sync, create a container/zone, persist user consent, authorize a sender, acknowledge changes, download document payloads, merge notes or delete content. No app launch/settings flow calls it automatically. Both user schema V8 and sidecar schema V2 are unchanged.

## Configuration gate and real adapter

SyncCloudActivationInspector.inspect requires an explicit SyncCloudInspectionConfiguration. A missing configuration fails before constructing a client. Malformed container/zone strings also fail before CloudKit initializers are reached. No default or placeholder container identifier is bundled in the app. The default factory creates CloudKitInspectionTransport, a real implementation; offline fixtures exist only in tests.

The caller must first provision and verify the real signing capabilities and container. The environment property labels local scope isolation; it **does not select or override CloudKit's server environment**, which comes from the signed build. A valid-looking string alone is not proof of entitlement or permission. See [CloudKitDevelopmentSetup.md](CloudKitDevelopmentSetup.md) for the pending setup gate. The inspected signed Release app still has application identifier 62TPVT35FP.com.local.notesapp and no iCloud entitlements.

The adapter checks CKContainer.accountStatus and obtains the real user record ID. It reads only the private database's configured custom zone, from a nil zone-change token through the final page, requesting up to 200 changes per request and only the schema/kind/revision/deletion/hash header keys. CKAssets, user text, titles and drawing/PDF/image/font payloads are not requested. A missing zone, expired token, network error, per-record failure or unsupported header aborts the inspection; none is interpreted as an empty account. A genuinely empty existing zone is accepted only after its completed fetch.

Every fetched entity header requires schema 1, a canonical kind.UUID name, matching kind, UUID revision, supported deletion fields/hash and a nonempty server recordChangeTag. Locally prepared unsaved CKRecords cannot pass as server headers. Blob identities and hard-deletion record types/names are checked too. Unknown future records fail closed. Genuine positive server-header/token decoding is a configured-container acceptance task, not something simulated with private API setters.

The collector processes updates and deletions over all pages, retains historical entity deletions for review and replaces earlier observations with later ones. Duplicate/ambiguous changes within a page and cycling/nonprogressing cursors fail. An empty final tail can keep the immediately prior cursor. Account identity is checked before and after enumeration; a scoped CKAccountChanged observer invalidates the result even if an account switches away and back during the request. Task cancellation is checked at boundaries; immediate interruption of an in-flight SDK network request is not claimed.

The baseline holds only value metadata, its verified scope, snapshot UUID and opaque final token. Tokens are securely archived by the real adapter and are not interpreted. This transient inspection does not advance or persist CKSyncEngine state. Its current caps are 2,000 pages, 400,000 retained entity/blob/deletion identities and 1 MiB per token. Token-history detection stores hashes rather than all token buffers. Collections still grow with the account; these caps are not peak-RAM or latency measurements.

## Fresh local comparison

Cloud inspection must run **before** DocumentWorkspace.prepareCloudActivationReview, so network waits do not hold the editor's workspace operation gate. The workspace then flushes both actual canvases and captures fresh local metadata using a background-created ModelActor. SyncStateStore verifies the active lease, completed local enrollment, recovered receipts, source library ID and exact remote scope before producing a review. It revalidates the lease after suspension.

The initial enrollment counts are cached progress, not a current library snapshot. The new read-only inventory includes every current live identity and pending operation/revision. Its shared SyncIdentityInventory helper performs the same projected 256-row UUID fetches used by enrollment. The enrollment refactor preserves existing identity digests, journal tokens and atomic-save semantics. No source content is decoded or copied by the review scan. The existing local 200,000 combined identity/deletion preparation limit applies.

| Observed situation | Advisory disposition |
| --- | --- |
| Local live record absent remotely | Local-only record needs review |
| Remote live record absent locally | Remote-only record needs download/validation |
| Same live identity on both sides | Compare full content and preserve both until resolved |
| Local pending deletion, with or without a remote record | Review the deletion; do not automatically remove remote content |
| Remote tombstone/historical deletion | Review remote deletion; do not automatically delete local content |

Even equal IDs/revisions are not treated as verified equal content from headers alone. Absence on either side never becomes an inferred destructive operation. The result contains no save/delete commands and no upload-authorized flag. Actual incoming payload verification, editable conflict copies, restore remapping and conflict-resolution UI remain future work.

Each review is bound to the library/enrollment, lease generation, scope, fresh local identity/operation/revision fingerprint and remote baseline identity/fingerprint, including token and header revisions/tags. Revalidation rejects changed inputs instead of silently applying an old review. This is snapshot validation, **not a live account authorization or eternal server snapshot**. The future opt-in coordinator must observe account changes for the full workflow, verify the current account again and refetch/revalidate server change tags before any write. No persistent activation consent or sender grant is implemented here.

## Verification and next integration

All **103 host tests** pass (101 Swift Testing plus two XCTest metadata cases). Eight new tests cover missing/malformed configuration before client creation, complete multi-page enumeration and empty final tails, account switch/notification/unavailability, ambiguous/duplicate/unsupported/interrupted/nonprogressing streams, cancellation, unsaved-record rejection, conservative review decisions, stale local/remote/session inputs, actual read-only user-store capture, real metadata edits, wrong scope, missing enrollment and incomplete baselines.

All **21 selected native tests** and the signed Release build pass. The real two-editor integration constructs an explicitly labeled offline baseline, performs the workspace review and verifies unchanged pending revision tokens, both canvas identities and editable three-stroke ink. These fixtures test policy and persistence; no account or network was contacted. The real CloudKit adapter compiles using public APIs available below the iPadOS 17 deployment target, but its genuine account/private-zone round trip still needs configured-device testing. See Validation.md for exact logs/results.

Next configure the development container and signing, add controlled custom-zone provisioning and the real opt-in coordinator, then run this read-only inspector against a development account before adding any sender. After that, validate actual engine serialization, incoming apply recovery and conflict preservation on two devices. The offline-v1-first decision is unchanged. The verified inspection work was subsequently organized into scoped local commits at the owner's request. No installation or push was performed.

Apple reference: [recordZoneChanges](https://developer.apple.com/documentation/cloudkit/ckdatabase/recordzonechanges(inzonewith:since:desiredkeys:resultslimit:)) documents selective keys, per-record failures, pagination and opaque change-token handling.
