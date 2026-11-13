# Phase 4 — Study

## Migration plan (before implementation)

The current store is V5. Freeze its four model definitions before introducing V6. V6 adds StudyDeck, Flashcard and ReviewRecord; existing folder/notebook/page/section fields and file paths remain unchanged. Register an additive lightweight V5 → V6 stage in the existing migration plan; verify both a real V5 disk-store upgrade and older-store migrations before installing on iPad. Never delete or recreate the user's store on migration failure.

Decks own cards; cards own review history. Optional notebook/page references are UUID values, independent of page order and SwiftData cascade deletion. Source lookup checks both IDs, notebook membership and Trash status before opening through the current workspace/save boundary. Missing sources preserve study content.

Study mutations use a dedicated main-actor ModelContext with explicit saves and rollback, so study failure cannot roll back pending editor metadata. No changes to PencilKit drawing files or export are needed. Retain local modal-sizing edits. Phase 4 introduces no networking, accounts, AI, purchases or external dependencies.

## Delivery checks

- Real persisted deck/card CRUD, optional notebook/page links and recoverable deletion.
- Deterministic, documented scheduler independent of SwiftUI; atomic card-progress/history save.
- Real due counts, question/answer review, ratings, saved progress and source navigation.
- Native iPad UI, accessibility/Reduce Motion, empty states and error handling.
- Migration, scheduler, persistence, source-ID and native integration regressions; signed build and iPad installation.

## Implemented architecture

| File or area | Responsibility |
| --- | --- |
| Core/Models/StudyDeck.swift | Deck title, optional notebook UUID, creation date, recoverable Trash and card ownership |
| Core/Models/Flashcard.swift | Question/answer, permanent source UUIDs, schedule/progress, timestamps, Trash and review ownership |
| Core/Models/ReviewRecord.swift | Immutable rating/date/next-date/interval snapshot and scheduler version |
| Core/Persistence/SchemaV5.swift | Frozen pre-Study schema |
| SchemaVersions.swift / PersistenceController.swift | Current V6 schema and explicit V5 → V6 migration |
| Features/Study/Services/ReviewScheduler.swift | Pure Sendable ReviewScheduling boundary and deterministic V1 algorithm |
| Features/Study/ViewModels/StudyViewModel.swift | Dedicated-context queries, validation, saves, rollback and current source lookup |
| Features/Study/ViewModels/StudyReviewSession.swift | Due-ID snapshot, question/answer visibility and advancement after successful persistence |
| Features/Study/Views/ | Dashboard, deck list/detail, native edit forms, note capture, review and recovery |
| DocumentWorkspace / LibraryView | Flush outgoing ink, open an explicit permanent page ID, clear the pushed Study route and preserve return to Study |

The deck/card and card/review relationships have cascade rules for ownership, but this phase never permanently deletes study records. Study Trash stores trashedAt and excludes these records from counts and review queues. Restoring a deck preserves individually trashed cards in Trash. Restoration does not reset a schedule or history. Notebook/page references are UUID values rather than ownership relationships. A missing source can remain attached while editing the card's text, or the user can remove/replace the link.

New cards are due at their creation instant. The dashboard displays real **Due today**, total-card and active-deck counts. Due today includes overdue cards and all scheduled before the next local midnight, calculated with Calendar (including DST). Review queues contain only cards due at the current instant. If there are cards scheduled later today, the dashboard says nothing is due right now and shows the next review time. A minute-based TimelineView refreshes the presentation without database writes; calculations use the actual current instant rather than the timeline's rounded minute. Newly created cards therefore appear due immediately on the next view update.

Study reads small metadata/text records only; it does not load notebook drawings or PDF thumbnails. Sources are checked against current metadata in a fresh read context, then checked again by Library/Workspace before opening. Notebook/page membership and effective ancestor Trash are verified. The existing save boundary preserves outgoing PencilKit data. No original document file is changed by Study.

## Scheduler V1

This intentionally simple interval policy is not SM-2 or FSRS and is not a calibrated memory model. It is replaceable behind ReviewScheduling. All interval math uses elapsed seconds and an explicit review Date; each day below means exactly 86,400 seconds. Local-calendar day boundaries are used only for the dashboard's Due today summary.

| Rating | Next interval | Progress |
| --- | --- | --- |
| Again | 10 minutes | Reset successful repetitions to zero; increment lapses |
| Hard | max(1 day, previous interval × 1.2) | Preserve repetition count |
| Good, no successful repetition yet | 1 day | Increment repetitions |
| Good, exactly one successful repetition | 3 days | Increment repetitions |
| Good, two or more | max(1 day, previous interval × 2.5) | Increment repetitions |
| Easy | max(4 days, previous interval × 3.5) | Increment repetitions |

Every interval is capped at 365 elapsed days. Non-finite/negative prior interval input is sanitized; counters are bounded before arithmetic. A rating writes the new card schedule, repetition/lapse counts, updatedAt and one immutable ReviewRecord in the same explicit save. The record stores schedulerVersion = 1. Failed saves roll back that context; the visible card, revealed answer and session position remain available for retry.

A session snapshots due IDs in stable due-date/UUID order. Each card is rated once per session; Again is due in ten minutes rather than looping immediately. Skip advances without a record or schedule change, so the card remains due for a later session. Closing a review requires no separate commit: each rating has already saved. Reopening starts a fresh queue from persisted due dates; it does not restore an ungraded answer or exact skipped position.

## Usage and acceptance

1. Open Study in the Library sidebar; create a deck with + and optionally associate a notebook.
2. Open the deck, add question/answer cards, optionally select a notebook and exact page. Cancel must create nothing. Edit a card without resetting its review progress.
3. Alternatively, in a note/PDF use **… → Page → Create Flashcard**. Outgoing ink saves first. Choose/create a deck, then enter question/answer; the current page is preselected as the source. Source notebook decks are listed first. Text entry is manual; no stroke recognition or AI generation occurs here.
4. Review from the dashboard or a deck. Show Answer uses a restrained 3D turn, disabled under Reduce Motion. Long content scrolls; larger text adapts rating columns and can scroll the whole review. Hidden faces are excluded from VoiceOver. Rate or skip and verify live counts.
5. Open Source Note, confirm the exact page opens after reordering, then return to Study. Delete/Trash the source and confirm a recoverable message while the card remains editable.
6. Move a card/deck to Study Trash with confirmation and restore it. Check schedules and history survive; no files should be duplicated or removed.
7. Close/background/relaunch, verify saved reviews/cards, next review times and due counts. Repeat with portrait/landscape, narrow windows, dark appearance, VoiceOver, larger text and Reduce Motion on an iPad.

## Scope and compatibility

Native SwiftUI and SwiftData APIs compile against the existing iPadOS 17 deployment target. New Deck uses the compact short-sheet policy; card editing, capture, recovery and review use the expanded policy. There are no new entitlements, dependencies or external services. Migration failures retain the existing startup error behavior and never reset the store. Apple's [schema modeling and migration guidance](https://developer.apple.com/videos/play/wwdc2023/10195/) informed the additive migration plan.

Handwriting selection to cards, image/ink card faces, FSRS, notifications, advanced statistics, card import/export, cross-device sync and AI generation are not implemented in this phase. Practice All includes due and future cards in an ungraded session; graded review continues to use the due queue. This MVP keeps metadata in memory; very large study libraries may justify measured pagination later. No permanent Study Trash purge is provided.

## Executed validation — November 13, 2026

The full native suite passed 135 tests; the subsequent navigation pass passed 14 focused tests, including the fifth new Study integration case. The final due-today/UI pass reran all five Study integration tests successfully. All 37 host tests pass, including eight Study cases. The signed optimized Release build succeeded and installed over the existing iPad app with sequence 2860. Native screenshots were visually inspected. iPadOS 17 remains compile-checked; runtime checks use iPadOS 26.5. See [Validation.md](Validation.md) for exact coverage and physical-device acceptance limits. Source changes remain local and uncommitted, together with the preceding compact-modal work.

## Explicit sample deck

On November 13 the user requested a test deck. The development launch argument `--create-study-sample-deck` creates “Mazo de prueba · Repaso general” with eight Spanish question/answer cards, immediately due and independent of notebooks. Ordinary launches do not insert sample content. The operation uses a dedicated explicit-save context and a stable deck UUID; repeating it preserves existing cards, ratings, scheduling and Trash state. A non-content receipt in Library/Caches/StudySampleReceipt.json verifies the operation without copying the user's library. The focused sample regression passes and the signed Release build succeeds.

## Refined review presentation

The review screen now separates the card, turn control and rating region into stable layout areas. Both question and answer faces stay in the same card viewport. The four real rating controls remain in layout before reveal, with hit testing/accessibility disabled and a recall prompt in their space. Revealing fades in those controls rather than inserting another row and recentering the screen. The Reveal Answer / View Question control retains both label sizes, so its bounds remain stable as its label changes.

Tapping the card or using the explicit turn button flips it. The visible face changes at the midpoint of a restrained 3D turn. Reduce Motion switches faces without rotation/fade animation. The card uses centered rounded system typography, a semantic surface, quiet accent border and a small side label. Long text scrolls within the face. Short-height/large-text presentations use a full-content scrolling fallback with the same stable ordering. Ratings use balanced rows of four, two or one, with text, symbols, gentle color cues and actual interval previews. Color is not the only difficulty cue.

StudyReviewCard, StudyReviewControls and StudyReviewView own presentation only; models, stored cards, review history, scheduler rules and migration remain unchanged. Hidden faces/ratings are excluded from accessibility, and hidden rating controls cannot accept taps. The card exposes an accessibility turn action and the separate turn button remains available. A stale/double rating callback is ignored after the session advances. Source and Skip actions retain their existing behavior.

FlashcardPresentationTests resolves real SwiftUI bounds anchors to measure the card, turn button and Skip action before reveal, after reveal, after turning back and after advancing to a long-content card. The measurement consumer is test-owned; production anchors do not drive layout or write observable state. Integration tests retain real Study persistence/source navigation and capture dark, narrow and accessibility layouts. Native unit tests cannot synthesize a physical finger tap; tapping/scrolling/VoiceOver acceptance remains an iPad check.

Compatibility: ViewThatFits, ViewModifier plus Animatable, rotation3DEffect and the existing sheet policy compile for the iPadOS 17 minimum. The implementation avoids the deprecated AnimatableModifier protocol. Apple documents [Animatable](https://developer.apple.com/documentation/swiftui/animatable) and [rotation3DEffect](https://developer.apple.com/documentation/swiftui/view/rotation3deffect(_:axis:anchor:anchorz:perspective:)) for this presentation boundary.

Refinement validation (November 13, 2026): all six focused native tests pass, including measured stable bounds across three window sizes and advancing to long content. Final narrow/dark screenshots and earlier question/answer/accessibility captures were visually inspected. The signed optimized Release build succeeded and installed over the existing iPad app with sequence 2884. Physical touch/VoiceOver acceptance remains manual. Changes remain local, uncommitted and unpushed.


## Practice All and repeat rounds

Every nonempty deck now offers **Practice All**, independent of due dates and the card-list search filter. **Review Due Cards** remains the scheduled, graded queue. Practice All snapshots all active cards in the selected deck, including future cards, in stable creation-date/UUID order. Trashed cards and cards in other decks are excluded.

Practice uses the same card and fixed turn control, with **Next Card** after revealing the answer. It does not show scheduling ratings or interval promises. The interface explicitly says review dates are unchanged. Completing a practice round offers **Practice Again**, resetting the local position, face and round count; current active members of the original snapshot remain eligible. Deleted/trashed cards are filtered out on repeat. Newly added cards appear when starting a fresh Practice All session from the deck.

StudyReviewSession distinguishes scheduled and practice modes, with scheduled mode as the default for existing callers. Practice advancement never calls the storage mutation or scheduler. It leaves nextReviewAt, interval, repetition/lapse counters, updatedAt and ReviewRecord history unchanged, even if the card is already due. Scheduled ratings retain the existing atomic save-before-advance behavior; the session rejects grading a practice round. Practice round counts are local UI state, not persisted review history. No model/schema changes or migrations are required.

Acceptance: finish a deck with Good/Easy so no cards are due, reopen it and choose Practice All. Reveal/advance through every card, choose Practice Again, then close/relaunch and confirm scheduled dates and due counts remain unchanged. Compare Review Due Cards, which still records ratings. Check source navigation, skipping, card deletion/Trash and fixed control positions in both modes.

Practice validation (November 13, 2026): all 39 host tests and seven focused native tests pass. The regression verifies zero persistence writes during practice, unchanged scheduling/history and repeated rounds, while native bounds remain stable in both session modes across three window sizes. The zero-due deck, practice answer and Practice Again screenshots were visually inspected. The signed optimized Release build succeeded and installed over the existing iPad app with sequence 2892. Changes remain local, uncommitted and unpushed.
