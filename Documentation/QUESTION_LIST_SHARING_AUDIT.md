# Question List Sharing Audit

Read-only audit of the question list sharing feature, 2026-07-30. No code was changed.
Reviewed at commit `cdbac4c`.

Framing follows the deep-module vocabulary: a **module** is anything with an interface and an
implementation; its **interface** is everything a caller must know to use it correctly (not just the
type signature); **depth** is how much behavior sits behind how small an interface; a **seam** is
where an interface lives and where an **adapter** can be swapped in.

## Scope

| Layer | File | Lines |
|-------|------|-------|
| Callable functions | `functions/questionListShares.js` | 538 |
| Link/route helpers | `functions/shareRoutes.js` | 46 |
| Security rules | `firestore.rules` (`questionListShares`, `recipients`, collection-group) | — |
| Service | `TTB/Services/QuestionListShareService.swift` | 296 |
| Observable state | `TTB/Models/SharedQuestionListStore.swift` | 620 |
| Value types | `TTB/Models/QuestionListShare.swift` | 195 |
| Deep links | `TTB/Utilities/AppDeepLinkRouter.swift` | 99 |
| Views | `TTB/Views/Main/SharedQuestionListViews.swift` (13 types in one file) | 1220 |
| Tests | `Tests/QuestionListShareTests.swift`, `functions/questionListShares.test.js` | 357 / 507 |

Behavior matches `Question_List_Sharing_UX.md` and ADR
`docs/adr/0001-question-list-sharing-links-and-snapshots.md`. The domain language in `CONTEXT.md`
is used consistently in code — `share`, `recipient`, `snapshot`, `revoke` all mean what the
glossary says they mean. That consistency is worth preserving.

## High-Priority Findings

### 1. Recipients can read each other's user IDs — FIXED

> **Status: fixed, deployed, migrated.** Recipient identities now live only in the `recipients`
> subcollection. `recipientIds` is no longer written, and both `acceptedRecipientCount` writers derive
> the count from that subcollection inside their transaction. Existing documents were cleaned on
> 2026-07-30 and re-verified clean — see [Remediation](#remediation-finding-1) below.

`CONTEXT.md` states: "Recipients do not see other recipients." The implementation did not hold
that invariant.

`recipientIds: [uid, ...]` is stored **on the share document** (`questionListShares.js:44`, `:142`),
and `firestore.rules` grants an accepted recipient a read of that whole document:

```
allow read: if isShareOwner() || isAcceptedShareRecipient();
```

`QuestionListShare.fromFirestore` does not parse `recipientIds`, so the app never shows it — but
rules are the security boundary, not the client mapper. Any accepted recipient can read the raw
document and enumerate every other recipient's UID, plus `acceptedRecipientCount`.

Options, in order of preference:

- Drop `recipientIds` from the share document and derive the roster from the `recipients`
  subcollection (owner-readable already), keeping only `acceptedRecipientCount` on the parent.
- Or move the roster to an owner-only sibling document and keep the share document
  recipient-readable.

The cap check at `:124` is the only consumer, and it runs inside a transaction that could read the
subcollection instead.

<a id="remediation-finding-1"></a>

**Remediation applied.**

- `createQuestionListShare` no longer writes `recipientIds`.
- `acceptQuestionListShare` and `leaveQuestionListShare` each read
  `recipients.where("status", "==", "accepted")` through `transaction.get` and set
  `acceptedRecipientCount` from that result. The roster is gone; the count is derived from the
  documents it describes, so it can no longer drift (this also resolves the counter-drift item under
  Lower-Priority Findings).
- Rules are unchanged. No field-level read restriction exists in Firestore, which is why the data had
  to move rather than the rule tighten.
- The iOS client needed no change: `QuestionListShare.fromFirestore` never parsed `recipientIds`.
- Four regression tests added to `functions/questionListShares.test.js`; all four were confirmed to
  fail against the pre-fix callable. The fake Firestore in that file gained `transaction.get(query)`
  support, which it previously lacked.

**Migration applied, 2026-07-30 on `ttbp-9d652`.** Share documents written before this change carried
`recipientIds`, so the leak stayed open for existing data until cleaned:

```bash
cd Scripts/seed_questions
node remove_share_recipient_rosters.js --dry-run   # report only
node remove_share_recipient_rosters.js --commit    # delete field, repair counts
```

The script deletes `recipientIds` via `FieldValue.delete()` and repairs any drifted
`acceptedRecipientCount` in the same pass. The `--commit` run scanned 20 share documents: all 20 still
carried a roster and were cleared, and 2 had a drifted `acceptedRecipientCount` that was repaired
(for example `Gk03EBVHRG5x4S6TKM3B`, stored 1 with zero accepted recipient documents). A verifying dry
run afterwards reported 0 rosters, 0 drift, 0 documents needing updates.

**Ordering hazard, recorded because it nearly bit.** The migration ran while
`acceptQuestionListShare` had *failed* to deploy — `firebase deploy` hit "Quota exceeded for total
allowable CPU per project per region" in `europe-west1` on 10 of 30 functions, and a failed update
leaves the previous revision serving. The old callable writes `recipientIds` on accept and sets
`acceptedRecipientCount` from the roster length, so an accept in that window would have restored the
leak and collapsed the count to 1. Nothing was accepted; the dry run after the full deploy confirmed
it. The quota itself was the real blocker and is fixed separately by capping max instances
(`functions/index.js`, commit `70d8e48`).

Sequence for any future data migration in this repo: **deploy the functions first, confirm every
function reports success, then migrate, then re-run the dry run to verify.**

### 2. Account switching can leak the previous user's shares into the UI — FIXED

> **Status: fixed.** Listener resets are now serialized behind a single cancellable task, and every
> suspension point in the listener path re-checks that the user it started for is still signed in.
> See [Remediation](#remediation-finding-2) below.

`SharedQuestionListStore.userId` has a `didSet` that fires unstructured work
(`SharedQuestionListStore.swift:18`):

```swift
private var userId: String {
    didSet {
        if oldValue != userId {
            Task { await resetListenersForCurrentUser() }
        }
    }
}
```

`resetListenersForCurrentUser` removes the old registrations, then suspends at
`await service.setupOwnedSharesListener(...)` (the service is an `actor`), then assigns the new
registration. Nothing serializes two overlapping runs. With two auth transitions in quick
succession:

1. Reset A (user 1) removes listeners, suspends at the actor hop.
2. Reset B (user 2) runs, removes the now-`nil` listeners, suspends.
3. A resumes and assigns `ownedSharesListener` = registration for **user 1**.
4. B resumes and overwrites `ownedSharesListener` = registration for user 2.

A's registration is never removed. It keeps firing and writing user 1's shares into `ownedShares`,
which the Shared hub renders. The auth listener at `:426` clears the arrays on user change, but the
orphaned snapshot listener repopulates them.

Fix: hold the reset in a single cancellable `Task` handle, cancel-and-replace on each user change,
and check `Task.isCancelled` (or re-verify `userId`) after every suspension point before assigning a
registration.

<a id="remediation-finding-2"></a>

**Remediation applied.**

- `userId.didSet` now calls `scheduleListenerReset()`, which cancels the in-flight reset and awaits
  its completion before starting the next one. Serialization is what closes the leak: the earlier run
  can no longer resume past the later one and overwrite its registration.
- `resetListenersForCurrentUser` captures `targetUserId` once, then re-checks
  `!Task.isCancelled && isCurrentUser(targetUserId)` after `loadRememberedAcceptedShares` and after
  each `setupListener` call. On a stale check it removes the registration it just created rather than
  storing it, so nothing is orphaned.
- Both listener callbacks drop their results unless `isCurrentUser(targetUserId)` still holds. This is
  the defense that matters even if a registration were to survive: stale data never lands in
  `ownedShares` or `acceptedShares`.
- `loadAcceptedShares(for:expecting:)` and `loadRememberedAcceptedShares(for:)` re-check after every
  `await` and key their `UserDefaults` writes to the captured user rather than the current one — the
  latter was itself a latent cross-user write.
- `deinit` cancels the reset task.

**Not unit-covered, deliberately.** The race cannot be exercised through the existing tests: the
fixture path sets `service == nil`, and `resetListenersForCurrentUser` returns at
`guard !targetUserId.isEmpty, let service else` before any listener work happens. Covering this needs
an injectable sharing protocol with a fake that can hold a registration open across an `await` —
i.e. the seam extraction described under Design Assessment. Verified by compiling
(`xcodebuild ... -configuration Debug build` succeeds, no new warnings) and by reading the
suspension points; the behavioral claim rests on that, not on a test.

### 3. `previewQuestionListShare` is unauthenticated and performs a write

`permanentUID` is not called in `previewQuestionListShare` — `user?.uid` is optional
(`questionListShares.js:65`). Anyone holding a share code, signed in or not, receives `listName`,
`ownerDisplayName`, `questionCount`, `recipientCap`, and `acceptedRecipientCount`. That is arguably
the intended preview contract for a claimable link.

The problem is `refreshShareOwnerDisplayName` on that same path (`:417-428`):

```js
const ownerDisplayName = await displayNameForUser(db, share.ownerId);
if (ownerDisplayName !== share.ownerDisplayName) {
  await shareSnapshot.ref.update({ ownerDisplayName });
}
```

An unauthenticated caller can drive an unbounded number of Firestore reads (share query + user
document) and a conditional write per call, with no rate limiting. Move the display-name refresh to
accept time, or gate it behind `permanentUID(user)` and let preview return the stored value.

### 4. `sendQuestionListShareReply` is not transactional

Every other mutation in this module uses `db.runTransaction`. This one does not
(`questionListShares.js:272-293`): the `share.status !== "active"` guard at `:274` and the recipient
write at `:286` are separated by two awaited reads and an `answerSnapshotsForUser` fan-out. An owner
revoking concurrently can have a reply snapshot land on a revoked share.

The test at `questionListShares.test.js:248` ("accepted recipients lose reply access") covers the
sequential case only, so the race is not caught.

### 5. Cross-tier error handling is English substring matching

`QuestionListShareService.userFacingMessage(for:)` (`:37-91`) inspects `localizedDescription` for
prose fragments the backend happens to emit:

```swift
if searchableMessage.contains("owners cannot accept") { ... }
if searchableMessage.contains("recipient limit") { ... }
if searchableMessage.contains("not accepting recipients") { ... }
```

Two problems. First, the coupling is invisible: renaming a `HttpsError` message in
`questionListShares.js` silently degrades the client to raw server text, and nothing fails at build
or test time. The `HttpsError` *code* (`failed-precondition`, `resource-exhausted`,
`permission-denied`, `unauthenticated`) is already the machine-readable channel — use
`NSError.userInfo` / `FunctionsErrorCode` and treat the message as diagnostics only.

Second, these strings are hardcoded English in a project that has `TTB/Localizable.xcstrings`.

## Design Assessment

### `SharedQuestionListStore` is shallow

620 lines, and roughly 275 of them are a second implementation of the service. The seam is expressed
as an optional concrete type:

```swift
private let service: QuestionListShareService?
```

`nil` means "use the in-memory fixture." Ten methods each carry the branch — `createShare`,
`previewShare`, `acceptShare`, `loadAcceptedShare`, `fetchRecipients`, `disableLink`,
`regenerateLink`, `revoke`, `leave`, `sendReply`:

```swift
guard let service else {
    // ...20-40 lines of in-memory implementation...
}
```

Consequences:

- **"There may be no service" is part of the interface.** Every caller and every test crosses a
  seam that leaks an implementation detail of the test harness into production code.
- **The two adapters diverge silently.** `sendReply` is a no-op when `service == nil`
  (`:322`). `fetchRecipients` returns without touching state (`:235`). `markReplySeen` calls
  `service?.markReplySeen` and then mutates local state either way (`:328`). Tests exercising the
  fixture path assert behavior production does not have.
- **The fixture initializer changes meaning by build configuration.** `init(localOwnedShares:...)`
  wraps its body in `#if DEBUG` (`:60-81`); the `#else` branch ignores every argument and builds a
  live Firebase-backed model. Today this is not reachable in Release — `TTBApp.rootView` gates all
  harness roots behind `#if DEBUG` (`TTBApp.swift:56`) — but `UITestSharedQuestionRootView.swift` is
  itself **not** `#if DEBUG`-wrapped, unlike its four siblings, so it compiles into the Release
  binary as dead code whose fixture call silently resolves to the live branch. That inconsistency is
  what would turn a future mistake into a production network call.

Two adapters exist, so by the "one adapter is a hypothetical seam, two is a real one" test the seam
is genuine. It is only the *expression* that is wrong. Extracting a protocol —

```swift
protocol QuestionListSharing: Sendable {
    func createShare(listId: String, includeOwnerAnswers: Bool) async throws -> QuestionListShareCreationResult
    func previewShare(shareCode: String) async throws -> QuestionListSharePreview
    // ...
}
```

— with `LiveQuestionListShareService` and `InMemoryQuestionListShareService` adapters would delete
every `guard let service else`, remove the `#if DEBUG` from the initializer, make the model's
interface honest, and let `QuestionListShareTests` cover the real code paths instead of the fixture
branch. That is roughly a 40% reduction in the model with no loss of capability — the definition of
deepening.

### The `UserDefaults` accepted-share cache needs justification

About 60 lines (`rememberAcceptedShareID`, `rememberAcceptedShareIDs`, `forgetAcceptedShareID`,
`rememberedAcceptedShareIDs`, `loadRememberedAcceptedShares`, `rememberedLocalAcceptedShares`)
maintain a per-user list of accepted share IDs in `UserDefaults`, keyed
`acceptedQuestionListShareIDs.<uid>`.

Apply the deletion test: if this vanished, what complexity reappears? Only the latency or failure of
`setupAcceptedRecipientsListener`, the collection-group query authorized by the
`{sharePath=**}/recipients/{recipientId}` rule. So the cache exists to paper over an untrustworthy
listener, and in exchange it creates a **second source of truth** for "which shares did I accept" —
one that `loadAcceptedShares` overwrites wholesale at `:505` while `loadRememberedAcceptedShares`
merges into at `:566`. Ordering between them is not enforced.

Before keeping it, establish why the listener is unreliable. If the answer is "first-load latency
after accept," the narrower fix is the optimistic `upsertAcceptedShare` already performed in
`acceptShare` (`:195`), with no persistence at all.

### Presentation layer

`SharedQuestionListViews.swift` holds 13 view types in 1220 lines, against an `AGENTS.md` convention
of one major type per file and the standing backlog item to extract oversized SwiftUI views. Six of
those types read `@EnvironmentObject var sharedQuestionListStore` directly, so the model's whole
surface is the view layer's interface. Splitting the file is mechanical; narrowing what each view
needs from the model is the more valuable half.

## Lower-Priority Findings

- **Dead field.** `shareCodePrefix` is written on create (`:41`) and regenerate (`:192`) and read
  nowhere in the app, the functions, or the rules. Either it backs a planned lookup path or it
  should be removed.
- **N+1 fetch.** `loadAcceptedShares` (`:492-506`) awaits `fetchShare` once per recipient
  sequentially. Use a `TaskGroup`, or denormalize the share fields the hub row actually renders onto
  the recipient document.
- **Blind transactional update.** `markQuestionListShareReplySeen` (`:311-319`) calls
  `transaction.update(recipientRef, ...)` without reading `recipientRef` inside the transaction. It
  throws `NOT_FOUND` if the recipient document is absent, and it does not verify that `recipientId`
  is an actual recipient of that share (harmless today, since `assertOwnedShare` confines writes to
  the caller's own share).
- ~~**Drifting counter.** `leaveQuestionListShare` recomputes `acceptedRecipientCount` as
  `recipientIds.length` after filtering (`:251`). Any recipient document created before
  `recipientIds` was introduced is not represented in that array, so the count can drift below the
  true number of accepted recipients — silently loosening the cap.~~ **Fixed** alongside finding 1:
  the count is now derived from accepted recipient documents on both the accept and leave paths.
- **Duplicated constants.** The recipient cap `25` appears three times: `DEFAULT_RECIPIENT_CAP`
  (`questionListShares.js:5`), the `fromFirestore` fallback (`QuestionListShare.swift:75`), and the
  local-create default (`SharedQuestionListStore.swift:124`). The host `ttbp-9d652.web.app` appears
  in `QuestionListShare.shareURL(for:)`, `AppDeepLinkRouter.isSupportedWebHost` (with the
  `firebaseapp.com` alias), and `shareRoutes.js` `PUBLIC_HOST`.
- **Mutable shared error slot.** `@Published var error: String?` is publicly settable and written by
  every method on the model, including from listener callbacks. Callers cannot tell which operation
  failed. `performShareMutation` (`:612`) already centralizes the pattern for four methods; the rest
  set `self.error` inline.
- **Unlocalized user-facing copy.** `ShareError.errorDescription`, the
  `userFacingMessage(for:)` returns, and `QuestionListShareActivityPayload.make`'s
  `"1 question"` / `"N questions"` pluralization are all hardcoded English string literals.

## Suggested Sequence

1. ~~Finding 1 (recipient enumeration)~~ — done, pending the backfill run against the live project.
2. ~~Finding 2 (listener race)~~ — done; test coverage deferred to the seam extraction.
3. Findings 3 and 4 — backend hardening, both small and independently testable.
4. Protocol extraction at the service seam. Do this before finding 5, because honest adapters make
   the error-mapping change testable.
5. Finding 5 (error codes over prose) plus the localization pass.
6. Cache justification, then the view-file split.

## Relationship to `ARCHITECTURE_DEEPENING_AUDIT.md`

That document was written independently and overlaps this one. Where they meet:

- Its **AD-5** and **FIX-1** cover the same ground as Design Assessment here (the optional-service
  fixture path, the per-file `#if DEBUG` policy). It goes further: `TTB/UITestSupport/UITestAuthMocks.swift`
  has no top-level `#if DEBUG` at all, so a permissive auth provider compiles into release builds.
  That is a larger instance of the same defect than the one recorded here.
- Its **AD-5** also flags the `UserDefaults` accepted-share cache, matching the deletion-test
  reasoning above.
- **FIX-2 is a finding this audit missed** — since fixed. `previewQuestionListShare` and
  `acceptQuestionListShare` both applied the `shareIsClaimable` gate *before* the already-accepted
  check, so an existing recipient who reopened a link after the owner disabled it was told the link is
  not accepting recipients — contradicting `CONTEXT.md`, where disabling stops new claims rather than
  re-entry. Both callables now resolve already-accepted first, and require the share to still be
  active so a half-completed revocation cannot pass as re-entry. Recorded under FIX-2 in that
  document.

Treat `ARCHITECTURE_DEEPENING_AUDIT.md` as the authority for design/refactor sequencing (it has the
candidate IDs and deletion-test verdicts). This document stays the record for the sharing feature's
correctness and privacy findings.

**Line references drift.** The fixes for findings 1 and 2 changed line numbering in
`functions/questionListShares.js` and `TTB/Models/SharedQuestionListStore.swift`. Line citations in
both audits that point into those files past the edited regions are now approximate.

## Verification Notes

Nothing in this audit was verified by running the app, the test suites, or the emulator. Findings 1,
3, and the "lower-priority" items are established by reading code and rules. Findings 2 and 4 are
race conditions derived from reading suspension points and read/write ordering; both should be
confirmed with a targeted test before and after any fix.
