# Pending CloudKit development setup

The local preparation, recovery, enrollment and read-only inspection services are implemented. There is no configured container or user-facing activation flow yet. The November 25 signed Release inspection confirms team 62TPVT35FP, application identifier 62TPVT35FP.com.local.notesapp and no iCloud/ubiquity entitlements. No developer-account resource was created in this pass.

## Configuration work before real requests

1. Open the NotesApp app target's Signing & Capabilities with the intended Developer team. Keep com.local.notesapp for current-install testing; changing the app identifier requires a separate data-transfer plan.
2. Add the iCloud capability and enable CloudKit. This explicit CloudKit adapter does not use iCloud Documents, key-value sync or automatic SwiftData mirroring. Xcode can also add Push Notifications when CloudKit is enabled; background engine delivery still needs its later integration.
3. Select or create the intended real iCloud container in that capability. Its identifier starts with iCloud. and uses a unique reverse-DNS name. Confirm the actual identifier rather than copying a test fixture name from the repository.
4. Build with the updated provisioning profile and inspect the signed app's entitlements. Verify container association, CloudKit service and actual development/production environment. The inspection configuration's environment value must match signing; changing that value cannot switch servers.
5. Provision the chosen custom private zone in a controlled setup step before inspection. This milestone intentionally implements no zone-creation call. A zone-not-found response must remain a setup error, not proof that remote content is empty.

Xcode registration changes, container creation and provisioning are pending owner/team setup, not completed actions. Apple describes the capability/container workflow in [Configuring iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services).

## First configured-device acceptance

Pass the verified container/environment/zone explicitly to SyncCloudActivationInspector; do not change NotesApp's user store from cloudKitDatabase.none. First perform read-only checks on an existing empty development zone and a zone with known records. Confirm that assets are not requested, account changes invalidate enumeration, unsupported records and failed pages cannot appear as an empty library, and the result matches the bound account/zone.

Then wire an explicit opt-in/review flow around the already-prepared local library. Consent must be bound to fresh inputs and current identity; the advisory review is not a sender permission. Do not acknowledge proposals as successful uploads. Sending, downloads/apply recovery, conflict copies, genuine CKSyncEngine state round trips, two-device tests and production-schema deployment remain separate milestones.

The existing save dot continues to mean a local save. No activation switch or successful-sync label should appear until the real service is configured and the corresponding behavior is implemented.
