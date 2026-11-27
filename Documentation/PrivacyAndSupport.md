# Privacy and support preparation

Updated November 26, 2026. Applies to the current offline build, not to a future CloudKit release.

## Implemented

Settings → Privacy & Help provides Privacy and Data & Recovery, entirely offline. Backups also links to the recovery guide. The screens explain local storage, optional on-device recognition, user-selected import/sharing, retained Trash, uninstall risk, additive restore, unencrypted portable backups and separate system/Files-provider backups. They do not load a web page, contact CloudKit, attach notes or invent a support destination.

Resources/PrivacyInfo.xcprivacy is registered as a real app resource by generate_project.py. It declares no tracking, no tracking domains and no developer-collected data types for this build. Required-reason declarations:

| Category | Reason | Actual source use |
| --- | --- | --- |
| UserDefaults | CA92.1 | App-owned appearance, tools, palette, workspace and sort preferences; no shared app-group/global-domain keys |
| FileTimestamp | C617.1 | FileFingerprint and imported-font cache invalidation; local descriptor checks in SyncSourceFile/SyncStateDirectory; app-owned drawing/staging/state files |
| FileTimestamp | 3B52.1 | User-selected archive reads via BackupArchiveIO after the native picker and coordinated/security-scoped access |

File sizes are also read by integrity validation. There are no direct app calls to available-disk-space, active-keyboard or system-boot-time APIs. UIKit/framework internals are not claimed as hand-written API calls. Re-audit when changing code or dependencies. There is no analytics/ad SDK. CloudKit classes exist as unconfigured developer services; no startup/opt-in call or cloud entitlement exists.

Apple's approved reasons were checked against [NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) and [NSPrivacyAccessedAPITypeReasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc). See also [required-reason declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [App Privacy management](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).

## Still required before submission

The owner confirmed that public policy/support URLs and a support email do not exist yet. No URL, mail address, public page or contact identity was fabricated. This milestone does not complete R3 or publish a legal policy.

1. Choose the publisher identity and real monitored contact address; review the policy/support drafts below for that publisher and the final binary.
2. Publish accessible HTTPS privacy and support pages, add the verified links/contact inside Settings and enter them in App Store Connect. Decide how voluntarily received support correspondence is retained and deleted; disclose that separately from automatic app collection.
3. Generate/review Xcode's final distribution archive privacy report and confirm dependencies, signed entitlements and runtime behavior. A bundled-manifest test or development Release build is not this archive review.
4. Complete App Privacy in Connect based on the shipping app. Local processing does not automatically imply that a future support/backend/sync integration collects nothing. Revisit declarations before enabling iCloud or telemetry.
5. Determine encryption/export compliance for the final build. SHA-256 integrity checks are not backup password encryption; this work sets no exemption key.

## Draft privacy policy for publication

Review-ready content; not published. Publisher/contact details must be supplied before adopting this as the public policy. In-app information is implemented by PrivacyView.swift.

HeyNotes stores notebooks, handwriting, imported documents/images/fonts, flashcards and review history locally on your iPad. Settings and editor preferences are also local. This version requires no HeyNotes account, does not upload your notes or study activity to the developer, and includes no advertising, tracking or third-party analytics. Optional handwriting conversion runs on-device using Apple's Vision framework.

You choose files/photos using system pickers and choose any export or sharing destination. HeyNotes does not request unrestricted access to your photo library, contacts or location. Services you choose in Files or the share sheet handle exported copies under their own policies. iPad system backups and diagnostics may be handled by Apple under your device settings. Notebook synchronization is not enabled in this version.

Portable library backups contain editable private content, are not password-protected/encrypted by HeyNotes, and should be stored in a trusted location. Removing a notebook, folder, study item or page retains it for recovery. Removed pages are available in their notebook's Pages → Recently Deleted view and are not automatically expired. There is no permanent-erasure command in this build. Deleting the app can remove its local library; exported/shared/device-backup copies must be managed separately in their destinations. Make an external editable backup before uninstalling.

You can use the app offline, disable handwriting conversion, export PDFs/backups and restore retained items. There is no account to delete. Changes to these practices, particularly a future optional synchronization service, require updating this policy and the corresponding app disclosures before release.

## Draft support page for publication

HeyNotes works offline and requires no account. For help protecting your library, open Settings → Data & Recovery. To create an editable external copy, open Settings → Backups → Create Library Backup and wait for Files to confirm the save. A PDF export does not replace a library backup.

Restore through Settings → Backups → Restore from Backup. The verified preview shows actual counts, including removed pages. Restoration adds separate copies without replacing existing notes. Keep the original archive and check editable handwriting, PDF/image content, page order and Study source links after relaunch.

Restore notebooks/folders in Library Trash and Study items in Study Trash. For a page removed by a recovery-capable build, open its notebook → Pages → Recently Deleted → Restore. Older removals that already lost metadata cannot be automatically reconstructed by this feature.

If saving fails, retain the app and pending ink, use Retry Saving and check available storage in iPad Settings. Do not uninstall or clear data to resolve a save error. If an archive is damaged, retain it and try a different copy. When contacting the future support address, provide the app/iPadOS version and reproducible steps first; do not send private notebooks unless you explicitly choose to share a necessary sample. Actual contact and support-correspondence handling remain publisher decisions.
