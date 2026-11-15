# CloudKit preparation and proposed milestones

Product decision — November 14, 2026: **ship v1.0 offline and add iCloud after launch**. The sync milestones below are post-launch work and do not block the initial App Store release. See [ReleaseReadiness.md](ReleaseReadiness.md) for the launch critical path.

Status: the local backup milestone is implemented on `feature/library-backups`. CloudKit remains a design proposal; there are no cloud entitlements, containers, automatic uploads or sync indicators in this change.

## Current constraints

HeyNotes uses a versioned local SwiftData V6 store plus independently stored PencilKit drawings, immutable PDFs and images. Metadata references app-relative file paths; optional stable UUID references connect Study with source notes. Local saves and both visible editors must remain usable without connectivity or an iCloud account.

Turning on automatic SwiftData CloudKit synchronization alone would not synchronize these document files. The current schema also uses unique attributes and nonoptional relationship arrays. Apple's automatic SwiftData/CloudKit integration does not support unique constraints and requires optional relationships. Existing stores and frozen migration schemas must not be rewritten simply to switch a flag.

The proposed approach is an explicit adapter using **CKSyncEngine**, available from iPadOS 17, with a private custom record zone and `CKAsset` for file payloads. This preserves local model invariants and offers explicit per-page conflict/recovery behavior, at the cost of implementing durable sync bookkeeping. It requires a separate technical spike before adoption, not an empty abstraction added to the current app.

## Milestones and gates

| Milestone | Work | Acceptance gate |
| --- | --- | --- |
| 1. Local recovery | Complete library export, integrity validation, additive restore, source-link remapping | Reopen restored stores; preserve editable ink, originals and Study; failed restore cannot overwrite local notes |
| 2. Sync design and migration | Choose the container/zone/record schema; durable outbox, engine state, asset staging, revision and deletion design; frozen V6 migration fixture | Reopen pre-sync libraries without changing IDs, paths or content; local-only mode remains fully functional |
| 3. One notebook | Explicit opt-in; notebook/page records plus drawing assets; foreground receive/apply and retry | Two physical devices round-trip one real notebook offline/online, across process termination and account changes |
| 4. Full document content | Folders, sections, PDFs, images, margins, bookmarks, moves, ordering and Trash | Large/mixed libraries retain geometry and assets; document moves never re-upload identical binary content unnecessarily |
| 5. Study and release hardening | Decks/cards/reviews, reference resolution, conflict diagnostics and status UI | Concurrent reviews do not lose history; stable links survive conflicts/restores; production schema and TestFlight migration verified |

Each gate leaves a usable build. Do not present a local save dot as cloud success before the server has confirmed the corresponding revision.

## Record and asset design to settle before implementation

- Use model-type-plus-permanent-UUID record names; never page indices, titles, folder paths or SwiftData persistent implementation IDs. Represent ownership with stable record references/IDs. Resolve partial downloads without creating editable empty pages or deleting existing ones.
- Keep local app-relative paths private. Remote asset identity, content hash and revision must be independent of the file's device-specific storage location. Use immutable staged upload files that remain present until the engine has finished with them.
- Record each committed local change durably in an outbox. Persist CKSyncEngine serialized state and successful server record system fields/change tags. Handle crashes between SwiftData, outbox and filesystem updates with an explicit import/recovery journal and idempotent operations.
- Store per-page revisions and an agreed base revision. Two-device drawing conflicts must preserve both editable drawings in a recoverable conflict copy; merging `PKDrawing` bytes by timestamp is unsafe. Use deterministic policies for metadata conflicts, section/page ordering and folder-parent cycles.
- Treat deleted/trashed items separately. Use durable tombstones and retention rules before any remote hard delete; propagate references in a recoverable order. Do not allow an old offline device to resurrect or purge notes unintentionally.
- Keep review records as append-only events with stable IDs. Derive/reconcile scheduling state using an explicit versioned policy rather than letting conflicting counters discard one device's review.
- Coordinate remote apply with both live editor sessions. Finish pending local ink before importing a competing revision; refresh or defer background updates instead of replacing the active canvas during a stroke.
- Define opt-in, account unavailable/sign-out/account-switch behavior. Never silently clear the local library on an account event. Avoid uploading one account's local library into another account automatically.

## Configuration and verification prerequisites

The next implementation milestone needs the Apple Developer team/container configuration and development CloudKit environment. Enable only the capabilities required by the selected sync path, then validate signing, private database access, notifications, retry limits and offline operation on two devices. Development and production schemas are separate deployment steps; production rollout and App Store privacy information must reflect the final behavior.

Before enabling sync on existing user libraries: save a backup outside the app, test the migration against a frozen V6 fixture, exercise missing/corrupt assets and full disk, test retry/duplicate delivery, kill during upload/download/commit, conflict both handwriting and page order, restore a backup while sync is enabled, and change iCloud accounts. Backup restoration's collision remapping intentionally creates new sync identities, so future sync must upload restored copies as new content rather than replacing unrelated remote records.

## Apple references

- [Syncing SwiftData model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [Synchronize with the CloudKit sync engine — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10188/)
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
- [Exporting with the native document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:))
