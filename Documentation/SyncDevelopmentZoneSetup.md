# Controlled development-zone setup and provisioning blocker

Implemented November 25, 2026, after committing read-only inspection/review. No live container or zone was created.

## Verified Xcode account gate

The actual NotesApp target was inspected in Xcode's Signing & Capabilities. It uses automatic signing, bundle ID com.local.notesapp and a Personal Team. The Team menu offers only that Personal Team, None and Add an Account; no enrolled-program team is available there. Existing signing/capabilities were retained. This observation does not prove the owner has no membership elsewhere: a paid/team account may need adding or refreshing in Xcode.

Apple's [CloudKit setup requirements](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app) require an active Apple Developer Program membership and the necessary team permissions. Apple also documents what [Personal Team means](https://developer.apple.com/help/account/basics/about-your-developer-account/). Real container registration, CloudKit provisioning, custom-zone creation and real account testing are blocked until a suitable team is available. No membership purchase, account signup, legal agreement or credential entry was performed.

Before registering a permanent container, confirm its intended identifier with the owner; Apple's setup documentation states that created containers cannot be renamed/deleted. Preserve the current app/data while changing signing: export an editable backup before testing a different team's install and do not uninstall the existing app to work around a provisioning error. Any different app identifier/team-prefix installation needs its own data-retention verification.

## Implemented developer-only service

SyncDevelopmentZoneSetup has two explicit operations:

1. prepare(configuration:) validates the development configuration, verifies the available account and probes the custom private zone. It returns a scoped plan stating whether creation is needed. It makes no write request.
2. createIfNeeded(for:) is a separate call for the reviewed plan, to be invoked only after explicit developer confirmation. It checks the account again, rechecks current zone existence and skips creation if another client already created it. An originally existing zone that disappears requires a new plan; it is not silently recreated.

CloudKitDevelopmentZoneTransport uses the actual public private-database recordZone and modifyRecordZones APIs. Creation submits exactly one custom zone with an empty deletion list and validates the per-zone save result. It exposes no document-record, asset, subscription, user-store or deletion operations. A missing zone means missing setup only; the existing read-only inspector still rejects zone-not-found rather than claiming the account is empty.

Account identity and CKAccountChanged checks bracket setup. Cancellation is checked before writes and after asynchronous boundaries; no promise of immediately cancelling an in-flight SDK request is made. A save can succeed before a response/account-verification failure is received. Therefore errors after creation starts mean **verify the account/zone before retrying**, not “nothing happened.” Retry observes an existing zone and does not delete it or try to roll back remote state.

Both the coordinator and concrete transport are disabled outside DEBUG. The actual transport's initializer and create method also reject non-Debug usage, independently of the coordinator. A production environment configuration is rejected in Debug before constructing a client. These guards prevent this development helper from becoming an accidental Release setup path. A future production opt-in/zone coordinator is a separate milestone.

The configuration's environment value is not a cryptographic/signing attestation and cannot select CloudKit's server environment. Before using the Debug helper, verify the signed build's real container/service/environment entitlements. Debug alone does not prove that a development server was selected. No placeholder container or new entitlement was added by this implementation.

## Validation

All **109 Debug host tests passed** (107 Swift Testing plus two XCTest metadata cases), including six setup tests. Cases cover no client creation in unsupported configurations, read-only planning, explicit verified creation, reuse on retries, stale existence plans, changed accounts/notifications, a response lost after simulated server-side creation without cleanup and deterministic pre-cancellation.

An actual **Release host build/test** also passed the one non-Debug guard case and verified zero transport-factory calls. The other development-only cases are intentionally excluded from that Release test target. The app's signed iPad Release build succeeds with existing signing. Its Release configuration has no DEBUG condition. Two native live-editor integration tests pass; the previous broad 21-case run remains documented separately and was not rerun in this helper-only pass.

The fixtures simulate zone existence and results only in tests. Real SDK account access, record-zone owner normalization, actual save results and a genuine configured-zone round trip remain untested because of the verified team/provisioning gate. No real client was created or account contacted during tests. No notes, files, journal rows, sidecar schema, startup flow, user-facing switch or local-save indicator changed.

## Handoff

1. Add/refresh a suitable enrolled Apple Developer Program team in Xcode (or join/enroll in one with the required permissions).
2. Confirm the real container identifier, enable CloudKit under that team and verify signed provisioning without discarding local notes.
3. On a configured Debug device, explicitly inspect the proposed zone, review its account/creation requirement, create only if needed, then run the read-only header inspector.
4. Proceed to genuine engine-state, opt-in, sending, incoming recovery and two-device conflict tests only after this configured-account acceptance passes.

The six inspection commits requested at the start of this task were completed separately. At the owner's subsequent request, this setup helper, regression coverage and provisioning record were organized into scoped local commits. No push or installation was performed.
