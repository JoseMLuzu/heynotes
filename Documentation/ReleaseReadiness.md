# HeyNotes — release readiness audit

Audit date: November 14, 2026. Scope: source, working tree, model/migration design, tests, built Release metadata and existing PlainJot documents. This replaces the November 13 snapshot. **Owner decision: ship offline first; implement iCloud after launch.**

## Verdict

HeyNotes is a functional feature-rich MVP approaching beta preparation. It is not ready for public App Store release today. The next phase is focused quality and distribution work. There is no evidence that more templates, AI or cloud integration is necessary to validate the existing student workflow.

Avoid a misleading percentage complete: functional scope is broad, but physical acceptance and distribution gates remain open. No public ship date is committed.

## What is genuinely implemented

| Capability | Audit conclusion |
| --- | --- |
| Native foundation | Swift 6, SwiftUI, PencilKit, PDFKit, SwiftData V6, local binary actors |
| Library | Nested folders, favorites, Inbox, Trash, title search, sorting and PDF previews |
| Writing | Native ink/tools, zoom, gestures, palette profiles, Focus Mode, toolbar placement |
| Pages | Permanent IDs, sections/bookmarks, thumbnails, drag reordering and duplication |
| Documents | Selective PDF import, separate annotations, extended note margins, PDF export/sharing |
| Design | Adaptive appearance, personalized accents/folder colors, 16 templates and 57 covers, app icon |
| Study | Deck/card editing, source links, real due counts, V1 spaced repetition, history and practice rounds |
| Workspace | Tabs plus two independent visible editors |
| Editable backup | Complete portable backup/verified additive restore; local branch, not yet published to Git |
| Recognition | Opt-in phrase-to-font conversion prototype; not handwriting search or personal-font training |

[Detailed inventory and architecture](ReleaseReadiness.md#implemented-capabilities).

## Evidence obtained today

- **45/45 host tests passed**, including persistence, migrations, ordering, Study and six backup tests.
- **151/151 native simulator tests passed** on iPad Pro 13-inch (M5), iPadOS 26.5: the full suite, not only the 18 targeted tests from the prior backup milestone. Total: **196 passing tests**.
- Latest signed Release build was already built, installed and launched on physical iPad Air (5th generation), retaining app data. This audit inspected the existing artifact and reran tests; it did not upload or reinstall the app.
- Toolchain rechecked: Xcode 27.2 (27B52), Swift 6.4.2, iOS SDK 27.2, deployment target 17.0.
- Development main/origin/main are d2ab170. Working branch feature/library-backups has uncommitted backup work plus this documentation. No commit/push was performed.
- The suite emits SQLite warnings when some test fixtures delete temporary stores while model contexts remain alive. Tests pass, but test cleanup should be corrected; these warnings alone do not demonstrate corruption of the user's production store.

## Actual blockers versus optional features

**Release-blocking work / unaccepted gates:** missing privacy manifest and in-app policy/support entries; account/Connect/archive validation not verified; identity/version strategy; rights and listing assets; realistic recovery/migration and supported-device acceptance; physical Pencil/performance/accessibility verification; TestFlight feedback and final candidate freeze.

**Important product gaps that can follow v1:** Home/All Notes, real dated Recents/lastOpenedAt, global Quick Note, grid/list mode, recoverable page Trash, Spanish UI and storage diagnostics. Page-deletion safety still requires a specific launch decision; implementing page Trash should be promoted if tests cannot establish an acceptable deletion/recovery experience.

**Post-launch:** iCloud, global handwriting search, selected-ink cards, FSRS, PowerPoint, reminders/statistics. These are not failures of the current offline MVP.

## Risks and proportionate mitigation

| Risk | Finding | Next action |
| --- | --- | --- |
| Data ownership | Backups exist but physical Files-provider acceptance is pending; page metadata deletion lacks restore | Run external backup/recovery drill on copies; decide page-deletion policy |
| Interrupted operations | Atomic drawings/metadata saves are independent; no complete filesystem journal | Test interruption windows, retain original backup and orphan bytes; never silently purge |
| Performance | Bounded caches/prepared canvases and tests exist; real peak RAM/FPS not established | Instruments on long handwritten notes, large PDFs and split panes; fix measured bottlenecks |
| Compatibility | Minimum OS 17 compile-checked, runtime tests are 26.5 | Test minimum OS or deliberately revise minimum before distribution |
| Experimental conversion | OCR can misrecognize cursive/equations; original ink retained | Accept opt-in behavior on hardware or hide from the release |
| Artwork | Gallery-resolution cover atlas supplied by user | Verify distribution rights; assess small-screen quality and replace with originals where needed |
| Packaging | Notes display name, local bundle ID, 0.1.0/build 1, missing manifest | Final identity/privacy/archive gate; preserve development notes if ID changes |
| Maintainability | Several large view/paging files; no CI workflow | Targeted extraction when needed, regression coverage and release artifacts; avoid a rewrite |

## When can it ship?

Planning estimate: **4–6 calendar weeks with sustained development/QA**, assuming access to the developer account, policy/support details, artwork rights and suitable testing devices, and no major beta defects. Reference window from today: **December 12–26, 2026**, for planning only. Apple review timing is separate and not guaranteed.

Approximate work: recovery 3–5 working days; hardware/accessibility/compatibility 3–5; privacy/distribution 2–4 in parallel; listing/beta setup 2–3; beta 10–14 calendar days with correction buffer; final candidate 1–2 working days. These estimates are judgment, not measured velocity or promises; do not simply add overlapping tasks. Part-time work or additional v1 features extends the window.

**Ready means** all R1–R6 gates accepted, no unresolved critical loss/freeze/crash issue, final regression pass, realistic upgrade/recovery acceptance, truthful privacy/marketing, validated distribution archive and beta feedback reviewed. TestFlight could start earlier after the data/privacy/distribution gates; public release follows the full gate.

## Recommended next action

Accept the current backup on the physical iPad using an external copy and isolated restore, then complete privacy/support and hardware QA in parallel. Record results in [07 — Validation](Validation.md). Keep [iCloud](CloudKitPreparation.md) out of the v1 critical path.

[Master roadmap](ReleaseReadiness.md#release-roadmap) · [P0 backlog](ReleaseReadiness.md#release-gates) · [Store checklist](ReleaseReadiness.md#app-store-preparation).

## Implemented capabilities

Verified against production sources and the current working tree on November 14, 2026. Implemented, automated-tested and physical-device accepted are different states.

## Library and organization

- SwiftUI NavigationSplitView; adaptive visual grid; folders/subfolders with inline sidebar expansion, color indicators and contextual create/rename/move/favorite/Trash actions. Folder moves reject cycles.
- Notebook/PDF creation, title search, rename, independent duplication, metadata-only movement, favorites and recoverable folder/document Trash.
- Inbox is a virtual view of unfiled documents. Sorting supports Name, Recent and Type; Recent currently means modification activity, not a persisted last-opened date.
- PDF library cards show the original first-page preview. This is not a preview composited with the latest editable ink/margins.
- Missing: separate Home/All Notes/Recents destinations, lastOpenedAt, global Quick Note and grid/list switching.

## Editor and pages

- Real PKCanvasView handwriting: pen, pencil, highlighter, eraser variants, lasso, colors, widths/opacity, undo/redo, pinch zoom and finger pan.
- Apple Pencil double-tap integration; movable quick palette with presets/profiles; toolbar placement at top/bottom/left/right; Focus Mode keeps paper and palette visible.
- Fit-page finger paging, interactive real-sheet transitions, bounded neighboring-page preparation and a 0.5-second hold to create the next page. Zoomed gestures pan. Reduce Motion is respected.
- Page creation, duplication, confirmed removal, thumbnail navigation and drag reorder; permanent UUIDs independent of order.
- Optional notebook sections with ordering and page assignment; named bookmarks, direct current-page bookmark action.
- Student tools: study tape, ruler/vector shapes, typed text, image insertion and adjustable right-hand PDF note margins.
- Limits: deleted-page metadata has no user-facing page Trash/restore; Undo is canvas/session scoped; force termination may lose ink since the last checkpoint.

## Documents and paper

- Native PDF file picker with whole-document, single-page, multi-page and validated range selection. Imported source is copied privately and never destructively annotated. Selecting a subset creates only selected page records while retaining the source PDF file.
- Independent editable ink/object layers; blank pages can coexist with PDF pages. Single-page and notebook PDF export plus native sharing include geometry, source content and extended margins.
- PDF export flattens PencilKit ink as bounded raster content; original PDF content and generated paper/text/shapes use the existing rendering pipeline. No claim of vector-ink export, editable PDF-native annotations or preserved interactive forms.
- Sixteen static paper layouts in a searchable gallery, including Cornell, lecture, planners, study plan, grid and dotted paper. Static Flashcard Sheet paper is separate from actual Study cards.
- Fifty-seven cover choices: five originals, forty supplied atlas designs and twelve subject covers. Confirm distribution rights and quality of supplied artwork before release.

## Study — Phase 4 is complete

- Stored StudyDeck, Flashcard and ReviewRecord with V5 → V6 migration; optional notebook association and source notebook/page UUIDs.
- Manual deck/card create/edit/recoverable deletion; real due/total counts, question/answer reveal, Again/Hard/Good/Easy and persisted progress/history.
- Replaceable deterministic V1 scheduler; graded due reviews and ungraded Practice All/repeat rounds are distinct.
- Open Source Note navigates to the permanent page ID and handles missing/trashed sources gracefully. No question generation or handwritten selection-to-card feature.

## Workspace and appearance

- Persistent open tabs/recent-tab history; up to two live independent editor sessions with resizing, focus and pane swaps. Closing/replacing saves affected canvases first.
- Single application window, not full iPad multi-window collaboration. Inactive tabs retain navigation metadata rather than unlimited live canvases.
- Soft-blue default accent, adaptable custom accents, dark mode, folder colors, glass-style toolbar/control groups, compact short forms and expanded longer forms.
- Dove/pencil icon exists in AppIcon assets. Built display name is still Notes, version 0.1.0/build 1, bundle ID com.local.notesapp. Final distribution identity is undecided.

## Storage, backup and architecture

- Swift 6, iPadOS 17 target, feature-based lightweight MVVM; SwiftData V6 and frozen V1–V5 migration history; FileManager/DrawingStorage actors with relative binary paths.
- Per-page editable PKDrawing files; 650 ms debounce, atomic checkpoints and explicit flush on page/tab navigation, background and export. Failed writes preserve pending ink and block unsafe navigation.
- Complete .heynotesbackup export/verified additive restore includes metadata, ink/checkpoints, PDFs, images, inserted content, Study history and Trash. Existing IDs are retained where possible; collisions remap imported links and use a fresh file namespace.
- Backup is implemented on feature/library-backups and installed on iPad, but remains uncommitted/unpushed. No CloudKit capability or upload is enabled.
- Backup limits: uncompressed/unencrypted; preferences/Undo excluded; finite manifest limits; no filesystem/SQLite recovery journal, automatic schedule or automatic orphan purge.
- Fingerprinted bounded PDF/thumbnail/prepared-page caches and memory-warning release. Cache budgets do not establish a hard application RAM cap.

## Experimental handwriting style

On-device Vision recognizes short phrases and converts them into editable text using installed handwritten fonts; original ink is retained for recovery. English/Spanish recognition is offered. This is not personal handwriting training, global search, ink smoothing or equation recognition. Keep opt-in and decide whether to ship it after device testing.

## Engineering observations

144 app Swift files and approximately 11,922 source lines at audit time. Largest files are LibraryView (543), EditorView (401) and PaperCanvas (389). Architecture is workable; reduce complex view/paging responsibilities only when fixes justify it. A broad rewrite would increase launch risk. No CI workflow or localization catalog was found; automation/localization are explicit backlog items.

See [validation evidence](Validation.md), [remaining work](ReleaseReadiness.md#release-gates) and [release findings](ReleaseReadiness.md).

## Release roadmap

## Delivery roadmap

| Milestone | Work | Exit gate | Planning allowance |
| --- | --- | --- | --- |
| R1 · Protect data | Accept real-device backups, migration, save/recovery and deletion behavior | Restore an external backup into an isolated library; original library and source links remain correct | 3–5 working days |
| R2 · Quality | Physical Pencil/Instruments, accessibility, oldest/current OS, large PDFs and split editors | No unresolved data-loss/freeze/crash issue; hardware evidence recorded | 3–5 working days |
| R3 · Privacy and support | Manifest, policy/support and accurate privacy/export declarations | Archive privacy report reviewed and live in-app URLs work | 2–3 working days; can overlap quality work |
| R4 · Identity and distribution | Name/bundle-ID transfer decision, account verification, signing and archive validation | Exact production archive validates; account setup verified | 1–2 working days; account delays separate |
| R5 · Listing and review materials | Original samples, artwork rights, screenshots, pricing decision, listing and review notes | Accurate materials accepted by owner | 2–3 working days; can overlap R1/R2 |
| R6 · Beta and release candidate | Internal/external TestFlight, feedback fixes, final regression, tag/artifacts and controlled release | R1–R6 accepted; owner authorizes submission and publication | 10–14 calendar days beta plus 1–2 final preparation days; Apple timing separate |

Estimate: **4–6 calendar weeks of sustained work**, assuming timely account/assets access and no major defects. From November 14 this suggests an internal planning window around December 12–26, 2026, not a promised release date. Part-time work, unavailable minimum-OS hardware or beta defects extend it. Read the detailed estimate in [the audit](ReleaseReadiness.md).

## After launch

First stabilize actual support/beta findings. Then implement iCloud in gated slices: migration/outbox → one notebook on two devices → documents/folders → Study/conflicts. Home/All Notes/Recents/Quick Note, grid/list, local handwriting search, FSRS and PowerPoint remain separate product increments.

## Release gates

Updated November 14, 2026. v1.0 is offline; iCloud is post-launch. Open boxes mean unaccepted work, not an assertion that the corresponding implementation is missing.

## Completed — do not schedule again

- [x] Phases 1–4, including real Study/decks/cards/reviews/source links.
- [x] Nested folders, favorites and folder/document Trash; sections/bookmarks.
- [x] Tools, palette profiles, Focus Mode, toolbar placement, templates and subject covers.
- [x] Selective PDF import, PDF margins/export and first-page library previews.
- [x] Tabs and two-document workspace; short-content modal sizing.
- [x] Git repository and published main at d2ab170.
- [x] Portable library backup/restore implementation and automated checks; local feature branch only.

## P0 — v1.0 release blockers and acceptance gaps

| ID | Work | Acceptance |
| --- | --- | --- |
| R1 | Data recovery and backup acceptance | External Files backup restores into an isolated library; ink remains editable; PDF/images, sections, Trash and Study links survive relaunch; existing library is unchanged |
| R2 | Physical quality and accessibility | Dense notes/long PDFs/two panes on iPad; no reproducible freeze, crash or lost committed ink; VoiceOver, larger text, contrast, Reduce Motion, rotation and supported OS verified |
| R3 | Privacy and support | PrivacyInfo.xcprivacy accurately covers used required-reason APIs; archive privacy report checked; published policy/support and accessible in-app links; truthful App Privacy answers |
| R4 | Production identity and distribution | Final name/identifier decision, existing-note transfer plan if ID changes, version/build progression, active account/agreements verified, distribution archive validated |
| R5 | Listing, rights and review materials | Original sample content, icon/cover rights, accepted iPad screenshots, actual feature claims, age rating, review instructions and contact ready |
| R6 | TestFlight and final candidate | Internal/external beta feedback reviewed; blocking issues fixed; upgrade and recovery retested; regression suite passes on the frozen release candidate |

R1 also requires an explicit decision about page deletion: implement recoverable page removal or ship clearly confirmed deletion with honest limits and external-backup guidance. Retained drawing bytes alone do not constitute a recoverable page Trash.

## P1 — valuable work, not automatically required for first release

- [ ] Recoverable page Trash with sufficient metadata to rebuild page order/content/source links. Promote before beta if deletion tests reveal a data-loss risk.
- [ ] Home / All Notes / dedicated Recents, lastOpenedAt distinct from updatedAt, global New Quick Note, grid/list. Current Library and modification sorting already work.
- [ ] Short offline first-run/help guide for Pencil, paging, palette, Study ratings and backups.
- [ ] Decide English-only launch versus Spanish localization. English-only can ship if listing/language claims match; multilingual support adds scope.
- [ ] Storage diagnostics and explicit cleanup policy; never automatically delete orphan/retained data without recovery design.
- [ ] CI for host/native checks and retained build artifacts; improve temporary-store test cleanup to avoid SQLite open-file removal warnings.
- [ ] Review experimental handwriting conversion: accept exact limits or hide it from release/marketing until reliable.

## Post-launch — approved direction, separate milestones

- [ ] iCloud: see [06 — gated sync plan](CloudKitPreparation.md). Do not block v1.0 on cloud setup.
- [ ] Navigation improvements, local handwriting search, selection-to-card capture and PDF text search, each with independent acceptance and scope approval.
- [ ] FSRS, richer card faces/import/export and review reminders after real Study usage.

## Dependency order

R1/R2 begin first. R3/R4/R5 can run alongside quality work. R6 needs a stable candidate and working distribution/privacy setup. Submission follows all six accepted gates. iCloud follows launch and a stable support baseline.

[Master roadmap](ReleaseReadiness.md#release-roadmap) · [App Store checklist](ReleaseReadiness.md#app-store-preparation) · [Test matrix](Validation.md).

## App Store preparation

Re-audited November 14, 2026. v1.0 is offline; iCloud will be a later update. Planning only: no upload, agreements, price change or submission was performed.

## Concrete repository and binary findings

| Item | Observed state |
| --- | --- |
| Product identity | HeyNotes in planning; built display name still Notes |
| Identifier/version | com.local.notesapp; 0.1.0 / build 1 |
| Devices/OS | iPad only, minimum 17.0; Catalyst and Designed for iPad on Mac disabled in project |
| Toolchain | Xcode 27.2 / Swift 6.4.2 / iOS SDK 27.2 |
| Icon | Real AppIcon asset exists and is selected in build settings |
| Privacy manifest | No PrivacyInfo.xcprivacy in sources or inspected Release app |
| Policy/support | No in-app URLs/entries found in Settings |
| Distribution | Signed Release installs; App Store archive validation, Connect setup and TestFlight not verified |
| Product completeness | Study and backups implemented; hardware release acceptance incomplete |

## R3 — privacy, support and declarations

- [ ] Add and bundle an accurate privacy manifest. Audit UserDefaults in settings/workspace/tools and file timestamp reads in cache fingerprints; use Apple's current approved reasons based on actual use.
- [ ] Inspect Xcode's archive privacy report and final dependencies/entitlements. No analytics, tracking, backend or CloudKit service exists in the current source.
- [ ] Publish policy/support URLs with real contact details and expose them inside the app. Explain local storage, optional system sharing/Files, editable backups, deletion, uninstall consequences and experimental recognition if shipped.
- [ ] Complete App Privacy from the final binary's actual collection behavior. On-device processing is not collection under Apple's definition; do not preselect answers solely from a product slogan.
- [ ] Complete encryption/export-compliance determination. Backup uses SHA-256 integrity hashing, not password encryption; do not set an exemption key by assumption.

[Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) · [App Privacy](https://developer.apple.com/app-store/app-privacy-details/) · [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)

## R4 — identity, account and packaging

- [ ] Confirm final name, subtitle, icon/art rights and branding availability. An icon is already implemented; name availability and rights are not established by that fact.
- [ ] Decide whether to retain the existing bundle ID or register a production ID. A new ID means another sandbox: export/recover current development notes explicitly before switching.
- [ ] Verify active program enrollment, account roles, required agreements and App Store Connect app/SKU. Development signing is not proof of these.
- [ ] Set launch version/build progression, archive with an accepted production Xcode release, validate signing and upload readiness; retain archive/dSYMs and tag the exact candidate.
- [ ] Confirm supported OS/device availability and intentional Mac/Vision distribution options.
- [ ] Recheck SDK requirements at submission. Apple's live requirements page currently lists Xcode 26+/iOS-iPadOS 26 SDK+ from April 28, 2026; the installed SDK 27.2 exceeds that version floor. Validate that this exact Xcode build is accepted for distribution. The older note's unverified April-2027 SDK claim is withdrawn.

[Live upload requirements](https://developer.apple.com/news/upcoming-requirements/)

## R5 — listing, commercial setup and review materials

- [ ] Choose v1 language(s), category, territories and pricing. One-time purchase remains the preference, not a configured price. Upfront paid distribution can use App Store pricing; an in-app permanent unlock requires separate StoreKit purchase/restore work.
- [ ] If charging, the owner handles applicable paid-app agreements/tax/banking. No subscription/paywall is needed for the current implementation.
- [ ] Prepare description, subtitle, keywords, copyright, age-rating/content-rights answers and review contact. Do not advertise iCloud, handwriting search, personal-font training, PowerPoint or vector-ink PDF export.
- [ ] Verify rights to bundled cover atlas/icon and use original sample notes/PDFs in all screenshots.
- [ ] Capture the accepted 13-inch iPad screenshot set; current accepted portrait sizes include 2064×2752 or 2048×2732, with landscape equivalents. Current native test attachments are QA evidence, not finished marketing screenshots.
- [ ] Review instructions: no login; create notebook, write, import PDF, create/review card, open source page, export/restore backup. Explain gesture/Pencil requirements and limits accurately.

[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) · [Review guidance](https://developer.apple.com/app-store/review/)

## R6 — TestFlight and launch

- [ ] Finish [hardware/recovery acceptance](Validation.md), upload only a validated candidate, and start internal testing before external student testing.
- [ ] Plan 10–14 calendar days of actual beta use, feedback and upgrade testing; this is our proposed quality window, not an Apple-mandated minimum. First external beta may require review; builds expire after 90 days.
- [ ] Resolve severe defects, re-run regressions, validate the final archive/listing/privacy answers and record known limitations.
- [ ] Owner authorizes the final submission, agreements and publication separately when ready. Prefer controlled manual release after approval and maintain a support/hotfix path.

[TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Release gate: every P0 accepted, editable recovery verified, privacy/listing accurate and beta feedback reviewed. Passing unit tests alone is not App Store readiness.

## Post-launch

The owner chose an offline v1.0. CloudKit, navigation additions and advanced study/search are separate gated updates. See [CloudKitPreparation.md](CloudKitPreparation.md).

## PlainJot project

The existing Notes — iPad project contains eight consolidated documents and six proposed Inbox tickets. The six original files retain their filenames and have historical copies under the vault’s .history/heynotes-release-audit-2026-11-14 directory. Parent relationships form one roadmap tree, with validation under the audit and release tickets under their actual checklists. Links and parent cycles were validated.
