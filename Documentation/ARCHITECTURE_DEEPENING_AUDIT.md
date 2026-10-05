# Architecture deepening audit

Date opened: 2026-07-30
Surveyed at: `feat/favorite-reminder-hig26` @ `cdbac4c`

Seven deepening candidates plus six standalone fixes. AD-1, AD-2, FIX-1, FIX-2, FIX-3, FIX-4, FIX-5,
FIX-6, and AD-3 have landed, and AD-4 has landed in part — their entries record what shipped and what
the original survey got wrong. FIX-6 was opened by AD-3's verification pass. Every citation below was
read and verified at the commit above — re-check `file:line` before acting, since the line numbers
drift.

**Five candidates in a row have had a load-bearing claim corrected by re-reading their own citations
before designing** (AD-1's two, AD-2's three, FIX-4's central one, AD-4's four, AD-3's eleven). In
AD-4's case the correction cut the entry in half: the half that shipped was justified by a bug the
entry did not state, and the half the entry argued for lost its justification. In AD-3's case it
replaced the proposed interface outright — the one harness said to prove the seam turned out never to
render the app. Do that pass first, every time.

## How to use this document

- Candidates are `AD-1` … `AD-7`; standalone fixes are `FIX-1` … `FIX-6`. Reference the IDs in
  commits and PRs so this file stays the index.
- **Open candidates are undesigned on purpose.** Each states the friction and a direction, not an
  interface. Pick one, grill it, then design it. See [Picking one up](#picking-one-up). Landed entries
  keep their original text below the status block, so the reasoning that led to the change survives
  alongside the corrections to it.
- Update the **Status** line on a candidate when it moves. If a candidate is rejected for a
  load-bearing reason, record an ADR under `docs/adr/` and link it here so the next survey does not
  re-suggest it.
- The vocabulary is deliberate: **module, interface, implementation, depth, seam, adapter, leverage,
  locality** (from the `/codebase-design` skill). Domain nouns come from `CONTEXT.md`. Don't
  substitute "service", "layer", "boundary" — the words are load-bearing across these entries.

## Scope and method

Scoped to the hot spots of the last 40 commits rather than the whole app, on the principle that
deepening pays off where change is actually landing: favorites and guest gating, the home question
surface, shared question lists, and the UI-test harness layer.

The test applied to every candidate is the **deletion test** — imagine deleting the module: if
complexity vanishes or concentrates in one place, it was earning nothing where it was; if it merely
reappears across N callers, leave it alone. Each entry records the verdict.

The generated HTML report that accompanied this survey lives in the OS temp directory and is
disposable; this file is the durable record.

## Status board

| ID | Candidate | Strength | Status |
| --- | --- | --- | --- |
| AD-1 | Deepen the Favorite module | Strong | **Landed** — state in `5fe7bd6`, `ce12e6b`, `82cc6f1`; the outcome half in `f913061`. The guest cap now reaches the UI through the returned outcome, and `shouldShowSignupPrompt` is retired. Read the entry |
| AD-2 | Collapse the answer-draft save protocol | Strong | **Landed** — `81e3d23`, `b5bd632`, `62f3b5c`, `b27bdbb`, `8ac2ea2` |
| AD-3 | One seam for the UI-test harness | Strong | **Landed** — the seam shipped as a modifier on a screen, not the injectable init the entry proposed (`5f4b751`, `457c764`, `f94071c`), and the leak list and the `#if DEBUG` gate followed (`efb2748`, `7af653f`, `6f24b42`). Production code no longer asks whether a UI test is running, except `TTBApp`'s dispatch and `AppCheckPolicy`; `HomeView` was a third until FIX-6 retired its guard. Eleven corrections, two of which changed the design. `docs/adr/0008`. Read the entry |
| AD-4 | Cut moderation out of the question read model | Worth exploring, weakened | **Landed in part** — `ba04a28`, `e893f10`, `d77c88b`, `c6bbc8c`. Moderation is out; the cached-derivations half is **not claimed and no longer justified**. Read the entry |
| AD-5 | Put a seam on the share-link service | Strong | **Landed** — `83e54f8`, `docs/adr/0009`, `7d61a86`, `9c24a65`, `163545c`. Seam, model migration, cache deletion, and the recipient-cap dedupe all shipped; closed out by issue #26. Read the entry |
| AD-6 | Name the answer-snapshot comparison | Worth exploring | Open |
| AD-7 | One notice seam | Speculative | Open |
| FIX-1 | `#if DEBUG` gaps ship test doubles in release | — | **Fixed** — see section |
| FIX-2 | Disabling a share link breaks recipient re-entry | — | **Fixed** — see section |
| FIX-3 | Guest favorites never migrate on upgrade | — | **Fixed and deployed** — see section |
| FIX-4 | Callables accept requests with no app attestation | — | **Fixed and deployed** — `11ec82c`, `065bd95`, `74d5c63`, plus `72c2493` for the deploy. Console steps and all six callables done 2026-08-01. One runtime check is still open; read the section |
| FIX-5 | `aps-environment` is hard-coded to `development` | — | **Fixed** — see section; simulator-verified only |
| FIX-6 | Three views build `BadgeModel` with no guard | — | **Fixed** — `f24ca60`, `387adf3`, `1a3a625`, `73414df`, `c520ce7`, `8ba1b01`. See section |

---

## AD-1 · Deepen the Favorite module — LANDED

**Status:** State half landed 2026-07-31 in `5fe7bd6` (service seam), `ce12e6b` (`FavoriteStore` + 19
tests), `82cc6f1` (wiring and deletions). Net 885 deletions against 313 insertions; full suite green.
The **outcome half landed 2026-08-05** in `f913061`: the guest cap
now reaches the UI through the outcome `toggle` returns, not a flag the guest store publishes. Read
*What landed later*. **Strength:** Strong. **Dependency category:** in-process.

> **What shipped.** `FavoriteStore` owns favorite state for guests and accounts behind
> `state(of:)`, `toggle(_:)` and a published list. Behind it: one precedence ladder (pending write →
> backend snapshot → the question's decoded flag as a cold-start seed), optimistic rollback,
> snapshot reconciliation, the guest cap, and migration. `FavoriteServicing` has two adapters — live
> Firestore and an in-memory fake — so the ladder and the rollback are testable without Firebase.
> Deleted: `FavoriteModel`, `QuestionModel`'s favorite cluster including its patching of six derived
> collections, `QuestionService.toggleFavorite`, `MostAnsweredViewModel.updateLocalFavoriteState`,
> `MigrationWriter`, the three view-local resolvers and the three copies of the write choreography.
>
> **Two claims in the original survey were wrong**, and the record should say so:
>
> 1. `sourceID == "favorites"` was **load-bearing, not vestigial**. `FavoritesView` sets
>    `expansionSourceID = "favorites"`, and without that clause the `favoriteState || modelState`
>    merge kept a just-removed favorite looking filled on the Favorites screen. It is gone now
>    because one owner cannot disagree with itself — not because it was dead.
> 2. The three guest-upgrade presentation paths are **not duplication to collapse**. They are forced
>    by presentation nesting, which `FavoritesView` documents in a comment: the screen is pushed
>    inside `ProfileView`, itself a `fullScreenCover`, so a root-owned sheet would present from
>    underneath a cover. Recorded as `docs/adr/0004-per-screen-guest-upgrade-presentation.md` so this
>    survey stops re-suggesting it.
>
> **Two things the tests found that the design conversation missed:**
>
> - UI-test harnesses bypass `AppEnvironmentRootView`, so nothing called `setIdentity` and the store
>   sat at `.signedOut`, refusing every toggle. `FavoriteIdentity.resolved` is now the single
>   derivation shared by the app root and a one-line harness modifier.
> - Deleting the `service == nil` local mode removed something two harnesses depended on: they build
>   a plain `AuthModel`, which reports signed out without Firebase, and local mode had quietly made
>   favorites work anyway. They now get an explicit fixture account through the in-memory adapter.
>   That is the AD-5 anti-pattern's cost, paid on the way out — and an argument for AD-3.
>
> **What landed later (2026-08-05).** The Direction asked for a narrow interface — "read the state,
> toggle it, **get the outcome back**". By the time this was finished, the three call sites already
> delegated to one consumer, `ToastCenter.toggleFavorite`, so the outcome was discarded in one place,
> not three. The fix made that consumer own the guest cap's UI consequence: `FavoriteToggleOutcome`
> gained `.guestLimitReached` (returned both for the add that lands on the cap and the toggle the cap
> blocks), `ToastCenter` gained `isGuestFavoriteLimitPromptPresented` and raises it from that outcome,
> and the root binds `FavoriteLimitSheet` to it. `GuestFavoriteModel.shouldShowSignupPrompt` and
> `dismissSignupPrompt()` are deleted, so the cap now reaches the UI through one channel. The stage-2
> `shouldShowGuestUpgrade`/`requestGuestUpgrade` sheet is unchanged.
>
> **Closed 2026-09-23 (issue #15).** The nesting question is settled by
> `docs/adr/0010-upgrade-prompt-presents-from-the-topmost-controller.md`: the Upgrade Prompt and the
> upgrade sheet it opens no longer bind a `.sheet` at the root. `AppRootBehaviourModifier` drives a
> `TopmostSheetPresenter` per flag, which presents over the topmost controller, so both appear over
> the expanded-card cover. Found while fixing it: the upgrade sheet was root-bound too, so the
> prompt's "Create Free Account" would have done nothing over a cover. The three per-screen
> `GuestUpgradeView` flags ADR 0004 describes are not moved yet.

**Files**

- `TTB/Models/QuestionModel.swift:42, 272, 309, 316-322` — `pendingFavoriteOverrides` + reconcile
- `TTB/Models/FavoriteModel.swift:24-25, 125-145, 163-171, 192-205` — a second override engine over the same fact
- `TTB/Models/GuestFavoriteModel.swift:4-9, 22-23, 76, 83-92` — guest limit (10) and milestone (3), plus `shouldShowSignupPrompt`
- Resolvers: `TTB/Views/Components/QuestionCard.swift:35`, `TTB/Views/Components/QuestionCardExpandedView.swift:125`, `TTB/Views/Main/MostAnsweredView.swift:122`
- Write choreography: `QuestionCard.swift:306-315`, `QuestionCardExpandedView.swift:165-174`, `MostAnsweredView.swift:359-369`
- Guest-upgrade presentation: `TTB/App/AppEnvironmentRootView.swift` (root sheet) vs `QuestionCardExpandedView.swift` (local flag) vs `TTB/Views/Main/FavoritesView.swift` (local flag)

**Problem.** Three modules each own part of "is this question a favourite", and every screen
re-derives it with a *different* precedence rule — `QuestionCard.swift:35` additionally special-cases
`sourceID == "favorites"`, the other two do not; `MostAnsweredView` resolves by linear scan instead of
the O(1) accessor. The same five-step write sequence is copy-pasted at three call sites, and all three
discard the guest result with `_ = guestFavoriteModel.toggleFavorite(questionId:)` even though
`GuestFavoriteToggleResult` exists to carry `limitReached`. Net effect: the same favorite button
behaves differently depending on which screen it sits on.

**Direction.** One module owning favourite state for guest and permanent accounts alike, with a
narrow interface — read the state, toggle it, get the outcome back — so the guest/permanent branch,
the optimistic override, and the limit rule all become implementation. Guest-upgrade presentation
should have one owner; the nesting constraint that pushed `FavoritesView` to a local flag needs
solving once at the root.

**Deletion test.** Concentrates. Deleting the three view-local resolvers collapses the precedence
rule into one place and makes `sourceID == "favorites"` either meaningful or provably dead. Deleting
only one of the two override engines just relocates state — the two published caches have to merge in
the same move.

**Test surface after.** The limit and milestone rules are already tested in isolation
(`Tests/GuestFavoriteModelTests.swift`, `Tests/FavoriteModelTests.swift`,
`Tests/QuestionModelFavoriteTests.swift`); resolution and the write choreography are currently
testable nowhere. Both become reachable through one interface, without Firebase.

**Open questions for grilling.** Is `sourceID == "favorites"` fixing a real staleness bug or is it
vestigial? Does the guest store stay separate behind the new interface, or merge? Where does the
guest-upgrade sheet live so that fullScreenCover nesting stops forcing per-screen flags? *(Answered
2026-09-23: on the topmost controller, driven from the root — `docs/adr/0010`.)*

## AD-2 · Collapse the answer-draft save protocol — LANDED

**Status:** Landed 2026-07-31 in `81e3d23` (delete the unreachable entry points), `b5bd632` (value
types and four ports), `62f3b5c` (`AnswerDraftStore` + 18 tests, mutation-checked), `b27bdbb` (wiring
and deletions), `8ac2ea2` (the editor holds one draft).
Full suite green: 188 unit + 28 UI, Release build clean.

**This one grew the codebase, unlike AD-1.** The two files that held the problem shrank by 485 lines
net — `QuestionModel.swift` +64/−289, `QuestionCardExpandedView.swift` +93/−353 — and that 642-line
deletion was replaced by 664 lines of new module across three files plus a net +357 lines of tests.
Total +1353/−817. The deletion test still holds in the sense that matters: the duplication is gone and
there is one owner. But the orchestration went from untested inline code to a documented module with
18 tests, and that trade costs lines. A future survey comparing this entry to AD-1's 885/313 should
know the difference is tests and documentation, not scope creep.
**Strength:** Strong. **Dependency category:** local-substitutable.

> **What shipped.** `AnswerDraftStore` owns the whole save choreography behind one entry point —
> optimistic write, upload fan-out, compare-and-swap re-persist, rollback, orphan-image cleanup —
> and owns no state. `AnswerDraft` is three slots by construction; each slot's image is exactly one
> of `none`, `saved`, `pendingLocal`, `pendingSuggestion`. `NormalizedAnswer` is the trimmed,
> resolved, three-of-everything shape, and `AnswerPersisting` accepts nothing else, so "normalize
> before you persist" is a fact about the types rather than a rule a caller must know. Four ports —
> `AnswerPersisting`, `AnswerImageStoring`, `AnswerCaching`, `AnswerSaveErrorReporting` — have live
> adapters and in-memory fakes.
>
> Deleted: five save entry points on `QuestionModel` plus `shouldPersistAnswers` and
> `currentAnswerMatches`; ~250 lines of orchestration in `QuestionCardExpandedView`; six copies of
> the slot normalizers (three in each file); four private upload types; the five parallel `@State`
> arrays that held one slot's state; `imagePreview`'s `clearsURL`/`clearsSuggestion` flags;
> `hasActiveImage`'s three-way OR. Boundaries a review will want to collapse are recorded in
> `docs/adr/0005-answer-draft-store-boundaries.md`.
>
> **Three claims in this entry were wrong**, and the record should say so:
>
> 1. **"Five save entry points with a mandated call order" was three.** `updateAnswer` had no callers
>    anywhere in the tree, and `saveAnswers` had no production caller — it was reachable only from
>    `updateAnswer` and from three of its own tests. The three live ones each had exactly one caller,
>    all in the same file. They were deleted first, in `81e3d23`, so the collapse's diff would not
>    appear to remove callers that never existed.
> 2. **The "two different rollback semantics" were one inconsistency, not two requirements.** The
>    no-upload path rolled the optimistic cache back when persistence failed; the upload path showed
>    an error and left the answer looking saved locally while the backend never received it. The open
>    question asked which caller needs different semantics — none does, since none had a second
>    caller. Unified on rollback for a failed text write, with no text rollback when only the
>    image-URL follow-up fails, which is correct because the text did persist. That is a real
>    behaviour change, pinned by `testTextPersistFailureInTheUploadPathAlsoRollsBack`.
> 3. **The three-slot rule was written out ~13 times across five files, not five times across three.**
>    `QuestionListShare.normalizedAnswers` is byte-identical to `QuestionModel`'s version, trimming
>    included, and `MostAnsweredView` has three inline copies in a single function. AD-2 claimed only
>    the save path; the rest are listed under "Not claimed" below.
>
> **What the tests found that the design conversation missed:**
>
> - Rollback has to restore the *stored* answer, not a normalized one. `NormalizedAnswer` carries no
>   `answeredAt` and no user id, so a port shaped around it would have quietly re-stamped every
>   rolled-back answer as freshly answered. `AnswerCaching` reads and restores `UserAnswer`, the same
>   precedent as `FavoriteServicing` speaking `Question`.
> - The ports had to be `Sendable` and the store's dependencies `nonisolated`, or the
>   `EnvironmentKey` default could not build the store — two warnings that are errors under the
>   Swift 6 language mode.

**Not claimed — follow-ups this left on the table**

- The pad-to-three rule still exists at `TTB/Models/Question.swift:43-52` (`UserAnswer.init`, the
  Firestore decode boundary), `TTB/Models/QuestionListShare.swift:111-117` (byte-identical to the
  normalizer AD-2 centralized), and `TTB/Views/Main/MostAnsweredView.swift:591-603` (three inline
  copies). All are read-path or another slice; `QuestionListShare` also carries the migration-ordering
  hazard recorded in `QUESTION_LIST_SHARING_AUDIT.md`. Routing display padding through the trimming
  normalizer would trim answers before display — a read-path behaviour change AD-2 has no coverage for.
- `AnswerDraftStore.persister` is optional, reproducing the existing local mode. That is the AD-5
  anti-pattern, kept rather than hidden behind a null-object adapter that would ship in the release
  binary. AD-3 or AD-5 should remove it.
- `QuestionCardExpandedView` still threads a `badgeModel` it never reads.

## AD-3 · One seam for the UI-test harness — LANDED

**Status:** Landed 2026-08-06 across six commits. The seam: `5f4b751` (harness capability), `457c764`
(the seam and all seven harnesses), `f94071c` (the two UI tests). The leak list and the gate:
`efb2748` (the service slots), `7af653f` (the sheet dismiss delay), `6f24b42` (the harness directory
and its test). It is **not** the injectable initializer this entry proposed — no harness renders the
app root at all. Full suite green: 247 unit tests and all fourteen UI suites.

**What the candidate asked for is done.** Production code no longer asks whether it runs inside a UI
test, with two exceptions, each of them structural rather than left over:

1. `TTBApp` dispatches to a harness root. That is the one place the choice has to be made.
2. `AppCheckPolicy` runs in `AppDelegate` before any `View` exists, so a view modifier is the wrong
   lifecycle stage for it. `testAHarnessArgumentCannotWeakenAReleaseBuild` keeps it honest.

`HomeView` used to be a third: its guard covered one `BadgeModel` construction site of four. FIX-6
moved that decision onto `AppEnvironment` and retired the guard.

`HarnessLayerIsolationTests` now pins both: a third production reader fails the suite.

The service slots moved onto `AppEnvironment` and the optionality stayed, which is not the entry's
Direction. Reading the code found that the three optionals are not one pattern and that null adapters
would change what the user sees — `docs/adr/0008` records both. Removing the optionality needs real
fakes and belongs to AD-5, which `docs/adr/0005` already named as the alternative owner.

Decisions recorded in `docs/adr/0008-one-harness-seam-applied-to-a-screen.md`.
**Strength:** Strong. **Dependency category:** ports & adapters.

> **The verification pass produced eleven corrections, and two of them changed the design.** That
> makes AD-3 the fifth candidate in a row whose citations were wrong somewhere load-bearing. Read
> these before trusting anything below them.
>
> 1. **The one harness said to prove the seam never rendered the app.**
>    `UITestSharedQuestionRootView` built a plain `AuthModel`, which reports signed out without
>    Firebase auth, so `AppRootView` showed `LoginView` and the deep-link sheet presented over the
>    login screen. Its test asserts only on the sheet, so nothing noticed. The authenticated root has
>    never been exercised by any UI test.
> 2. **"Move every harness onto the injectable init" was not achievable as written.**
>    `AuthenticatedRootView` builds `OnboardingViewModel()` with no seam and `OnboardingStateStore`
>    reads Firestore, so a harness on the real root lands on `OnboardingFlowView`. The gate is a
>    module this entry's file list never named. That is why `UITestSharedQuestionListRootView`
>    rendered `MainTabView()` directly — it was routing around the gate on purpose, not being lazy.
>    The seam moved to a modifier applied to a screen instead. See ADR 0008.
> 3. **The guest-upgrade sheet was never production-only.** `UITestCategoryQuestionsRootView`
>    re-declared it. So the count was three, not four, and all three were reachable through the one
>    harness that used the seam. "No UI test reaches them" was true; "untestable through any harness"
>    was not.
> 4. **Only two of those three are assertable, even now.** Foreground notification re-registration
>    runs on shared code but `syncCurrentDeviceRegistration` returns at its first guard without
>    Firebase auth and an APNS token, and `NotificationService` is a singleton with a `private init`.
>    ADR 0008 records it; AD-7 owns the fix.
> 5. **`AIService` already had an interface.** `AIServiceProtocol` exists at `AIService.swift:12` with
>    four adapters, and `TrioPromptModel` and `AIModel` already inject through it. The leak was
>    `QuestionCardExpandedView` holding the concrete actor. The type that genuinely lacked an
>    interface was `AnswerImageSuggestionService`, which both leak sites construct.
> 6. **`shouldSkipFirebaseConfiguration` does not skip Firebase configuration.** Both branches of
>    `AppDelegate.application(_:didFinishLaunchingWithOptions:)` call `FirebaseApp.configure()`; the
>    skip branch omits only `NotificationService.shared.configure(application:)` and the launch remote
>    notification. So the Direction's reason — "so 'no Firebase configured' stops being a view-level
>    branch" — rested on a premise the code does not hold. The guards prevented *network traffic*. The
>    flag is still misnamed; ADR 0008 lists that as not claimed.
> 7. **`HomeView:28`'s guard covers one `BadgeModel` construction site of four.** `ProfileView:612`,
>    `AnswersView:6` and `MostAnsweredView:403` build one with no guard, so harnesses open a live
>    badge listener today. Filed as **FIX-6** rather than folded in.
> 8. **`QuestionListsView:426` is a different shape from the other five.** It already sits inside
>    `#if DEBUG` and it delays a sheet dismiss for simulator timing rather than guarding a service, so
>    its retirement is a value on `AppEnvironment` read through an `EnvironmentKey`, not a seam move.
>    Still open with the rest of the leak list.
> 9. **`AppCheckPolicy.swift:48` is a seventh site, and it cannot move.** App Check installs in
>    `AppDelegate` before any `View` exists. ADR 0006 handed it here; ADR 0008 hands it back.
> 10. **The harness layer had grown to ~1253 LOC, not ~1150**, and every per-file count in the list
>    below had drifted. AD-1 added `UITestFavoriteService.swift`. FIX-1's "four membership exceptions"
>    is six.
> 11. **"Roughly 700 LOC goes" was wrong.** The harness roots and the old root lose about 320 lines
>    and the shared seam adds about 330, so the line count is close to flat. The entry counted the
>    duplication without counting its replacement. Eight wirings became one, and two unreachable paths
>    gained tests — that is the deliverable, not a line count.
>
> **What shipped.** `AppEnvironment` holds the eleven models and the launch deep link, with a `live`
> factory and a `uiTest` factory in `TTB/UITestSupport/` under `#if DEBUG`. `appEnvironment(_:)`
> installs the environment objects and is applied in every presentation context, including each sheet
> body — the app root and one harness used to re-list nine `environmentObject` calls four times between
> them. `appRoot(_:)` is that plus the whole cross-screen behaviour block. `AppEnvironmentRootView`
> went from 196 lines and an eleven-parameter init to 29 lines and one parameter, and it has no
> injectable init at all.
>
> Deleted: the six re-declared harness wirings, `TTB/Utilities/UITestAuthContext.swift` and the four
> `\.uitestAuthIsAnonymous` reads in `AIView`, `uiTestFavoriteIdentity` and its
> signed-out-to-fixture-account fallback, and `FavoriteStore.uiTest(corpus:)` with the second corpus it
> could disagree with.
>
> Two paths that no test could reach are now covered by
> `TTBUITests/GuestFavoriteUpgradeFunnelUITests.swift`: the favorite-limit sheet, and guest-favorite
> migration after an upgrade.
>
> **Two things the tests found that the design conversation missed:**
>
> - `AuthModel.linkAnonymousAccount` never updates `AuthModel`'s own state — it waits on the auth
>   listener, and `isAnonymous` is computed from `currentUser`. The harness provider called its
>   listener once at init and `UITestAuthUser.link` returned a new object without telling it, so a
>   fixture guest stayed anonymous after a successful upgrade. No test had ever driven an upgrade, so
>   nothing noticed. `link` now publishes, as real Firebase does.
> - The guest cap is ten and the largest harness fixture holds three questions, so a UI test cannot
>   tap its way to the cap. `UITestGuestFavoriteSeed` starts a harness one favorite below it, derived
>   from `maxGuestFavorites` so raising the cap cannot leave it stale.

**Files** — as surveyed, before the change; line numbers had already drifted (correction 10)

- `TTB/App/AppEnvironmentRootView.swift:40-67` — the injectable init; a real seam
- `TTB/App/UITestSharedQuestionRootView.swift:13-30` — the one harness that uses it (44 lines)
- Six harnesses that re-declare the wiring instead: `UITestSharedQuestionListRootView.swift` (221), `UITestHomeRootView.swift` (139), `UITestMostAnsweredRootView.swift` (115), `UITestProfileRootView.swift` (91), `UITestCategoryQuestionsRootView.swift` (61), `UITestAIRootView.swift` (55)
- Launch-argument leaks into production code — **six sites, re-counted 2026-08-02**: `TTB/Views/Main/HomeView.swift:28`, `TTB/Views/Components/QuestionCardExpandedView.swift:155-158` (two checks), `TTB/Views/Main/QuestionListsView.swift:426`, `TTB/Utilities/UITestAuthContext.swift:3-11` (read by `TTB/Views/AI/AIView.swift:6,19,23-24`), plus two AD-2 added: `TTB/Services/AnswerDraftPorts.swift:115` and `TTB/Models/AnswerDraftStore.swift:214`
- **AD-2 made this worse, not better.** `docs/adr/0005` claimed the `AnswerDraftStore` default retired one of the four leaks. It did not — it copied the check into two more places, and the `View` initializer still holds its two. The ADR is corrected; this list is the count that matters.
- `TTB/App/TTBApp.swift:55-83` — the single dispatch point (this part is good)

**Problem.** A real seam exists and is proven by one harness, but seven bypass it, so the UI tests run
against a second app wiring (~1150 LOC including `TTB/UITestSupport/`) that has drifted from
production. Four things exist only on the production path and are therefore untestable through any
harness: the favorite-limit sheet, the guest-upgrade sheet, guest-favorite migration, and foreground
notification re-registration. Meanwhile production views consult launch arguments to decide whether
they may construct a service.

**Direction.** Move every harness onto the injectable init, passing fixture data and fake adapters.
Give `AIService` and `BadgeModel` interfaces with null adapters so "no Firebase configured" stops
being a view-level branch, then retire `\.uitestAuthIsAnonymous` — production code should not have two
sources of truth for whether the user is anonymous.

**Deletion test.** Concentrates. The fixture arguments are real data; the re-wiring is duplication of
a path that already has one working instance. Roughly 700 LOC goes.

**Test surface after.** UI tests exercise the real root, so the guest-upgrade funnel becomes reachable
and the four divergences stop being invisible.

**Open questions for grilling.** Is the injectable init the right shape, or should it take one
dependencies value (the `AuthModelDependencies` pattern at `TTB/Models/AuthModelDependencies.swift:112-128`)?
Do harness fixtures belong in the test target rather than the app target?

## AD-4 · Cut moderation out of the question read model — LANDED (moderation only)

**Status:** Landed 2026-08-01 in `ba04a28` (dead members), `e893f10` (`Question`'s three moderation
operations + 17 tests), `d77c88b` (`QuestionModerating` + `QuestionModerationStore` + 13 tests),
`c6bbc8c` (wiring and deletions). 226 unit tests pass, up from 196.
**Strength:** was "Worth exploring", and the verification pass below **weakened its stated
justification while finding a real bug it did not state**. The moderation half shipped on the strength
of the bug. **The cached-derivations half did not ship and is not justified — see "Not claimed".**
**Dependency category:** in-process.

> **What shipped.** `QuestionModerationStore` owns the moderation corpus and the choreography behind
> every admin action, behind `QuestionModerating` with a live adapter on `QuestionService` and an
> in-memory fake. `Question` gained three named operations — `moderated(as:at:by:rejectionReason:)`,
> `featured(as:)`, `edited(text:category:languageCode:)` — each mirroring the `QuestionService` write it
> pairs with. Every store write is backend-first, so a refused write cannot leave an admin looking at a
> decision the backend rejected; the three "a failed write leaves the corpus untouched" tests are ones
> the old code could not have had, because reaching the local patch meant taking the
> `questionService == nil` branch, which skipped the backend call.
>
> Deleted from `QuestionModel`: `refreshAdminQuestions`, `addQuestion`, both `deleteQuestion`
> overloads, `updateQuestion`, `approveQuestion`, `rejectQuestion`, `setFeaturedPlacement`,
> `editQuestion`, `moderatedQuestion`, `copiedQuestion`, `removeLocalQuestion`, and the file's private
> `nilIfEmpty`. 687 lines → 424. `QuestionModel` no longer appears in `AdminQuestionView` except in one
> comment, and `ProfileView` stops injecting it. Boundaries a review will want to collapse are recorded
> in `docs/adr/0007-question-moderation-store-boundaries.md`.
>
> **The pre-existing `QuestionFeaturedPlacement.none` ambiguity warning is gone.** It sat in
> `rejectQuestion`, which passed `.none` into an optional parameter. The rule now lives inside
> `Question.moderated` and no caller passes a placement.
>
> **Two follow-ups this created, both in ADR 0007:** the moderation rules are now written twice — in
> `Question.moderated` and in `QuestionService.updateQuestionModeration` — and agree by test rather than
> by shared code, because the backend payload needs `FieldValue.delete()`, which no `Question` can
> carry. And `AdminQuestionView` owns the store with `@StateObject`, so the *view* takes a live
> `QuestionService()` with no seam. That is AD-3's question, not this one's.

**Not claimed — the second half of this entry did not ship**

- **"Let read-only derivations compute rather than cache-and-patch" was not done, and the verification
  pass removed its justification.** The entry rested it on "an admin write invalidates every card",
  which is false — see correction 2 below. `groupedQuestions` and `todaysQuestions` are still
  `@Published` caches recomputed by `updateGroupedQuestions()`. Anything revisiting this must start from
  a measurement, not from this entry: `Documentation/PERFORMANCE_PASS_PLAN.md` and
  `Tests/HotPathBenchmarkTests.swift` exist because these caches were put there deliberately, and
  `testBenchmarkTodaysQuestionSelection` measures the derivation the entry proposes to run on every
  read.
- **`Question.fromFirestore` still reads `Auth.auth().currentUser` (`Question.swift:195`)**, so decode
  tests still need a configured Firebase. Untouched. This is the smallest remaining piece of the entry
  and is independent of everything above.
- `upsertLocalQuestion` stays on `QuestionModel`: `fetchSharedQuestion` needs it to put a deep-linked
  question into the read cache.
- `publishUserCreatedQuestion` stays on `QuestionModel`. The entry grouped it with the admin cluster and
  was wrong — `TrioPromptModel` calls it.

> **Verification pass, 2026-07-31.** Every claim below was re-read before any design work, which is
> the step that changed the work in AD-1, AD-2 and FIX-4. It changed this one too. Four corrections,
> and the entry should not be acted on without them.
>
> 1. **The numbers are stale, because AD-1 and AD-2 already did part of this.** `QuestionModel.swift`
>    is 687 lines, not 1012. Two of the "ten responsibility clusters" are gone: favorite overrides
>    (AD-1) and the five save paths (AD-2). Eight remain. "Six derived collections stored as
>    `@Published` and hand-patched" is four published collections, of which two are derived from
>    `questions` (`groupedQuestions`, `todaysQuestions`); the hand-patching lives in
>    `upsertLocalQuestion` and `removeLocalQuestion`, whose only callers are the admin CRUD members and
>    `fetchSharedQuestion`.
> 2. **"Every question card observes the admin moderation cluster, so an admin write invalidates every
>    card" is overstated.** `QuestionCard` does observe (`@ObservedObject`), but
>    `QuestionCardExpandedView` takes a plain `let model: QuestionModel` and observes nothing. More to
>    the point, the invalidation comes from `@Published questions` changing, and every listener
>    snapshot writes it too — moderation is not special, and splitting moderation out does not reduce
>    invalidation. Do not justify this candidate on render cost.
> 3. **"They have no reader outside the admin screens" is wrong for one member.**
>    `publishUserCreatedQuestion` is called by `TrioPromptModel.swift:171` — a user feature, not an
>    admin screen. It cannot move into an admin module. The other seven CRUD members are
>    `AdminQuestionView`-only, as claimed.
> 4. **The real harm is narrower and concrete, and this entry does not state it.**
>    `refreshAdminQuestions` calls `replaceQuestions(getAllQuestions())` — the whole `questions`
>    collection, unfiltered — and then `updateGroupedQuestions()`. The public read model is normally
>    `seededQuestions + featuredHomeQuestions`, both filtered by their Firestore queries
>    (`QuestionService.swift:510` and `:536`, the second requiring `approved` and `featuredPlacement ==
>    home`). So once an admin opens the admin screen, `groupedQuestions` holds pending and rejected
>    user-created questions, and `CategoryQuestionsView` and `HomeView:85` render them. It heals only
>    when a listener next fires, which needs a write to a matching document — so it can last the whole
>    session. `todaysQuestions` is **not** affected: `TodaysQuestionSelector.select` filters
>    `source == .seeded`. Blast radius is admins only.
>
> **Done in this pass:** three unreachable members deleted and two narrowed to `private`, following
> AD-2's precedent of clearing dead entry points in their own commit so the split's diff does not
> appear to remove callers that never existed. `QuestionModel.fetchMostAnsweredQuestions` had no
> caller — `MostAnsweredView.swift:43` calls `QuestionService` directly.
> `QuestionModel.fetchUserAnswers` had no caller, and neither did the
> `QuestionService.fetchUserAnswers` behind it, so both went. `editQuestion(_:newText:)` had no caller;
> only the three-argument overload is used. `updateQuestion` and `deleteQuestion(_ questionId:)` are
> reachable only from inside the type and are now `private`. `QuestionModel.swift` 687 → 630 lines.

**Files**

- `TTB/Models/QuestionModel.swift` — 630 lines, `@MainActor`, 7 published, 4 Firestore listeners + 1 auth listener; eight admin/CRUD members remain in the interface
- `TTB/Models/Question.swift:195` — `fromFirestore` reads `Auth.auth().currentUser` to compute `isFavorite` (verified, still true)

**Problem.** Ten responsibility clusters in one module: read cache and derivations, listener/auth
lifecycle, favorite overrides, five save paths, user-answer cache, admin moderation CRUD, leaderboard
passthrough, deep-link fetch, an externally-writable error channel, and localization reads. Its
interface is nearly as wide as its implementation. Every question card observes the admin moderation
cluster, so an admin write invalidates every card. Six derived collections are stored as `@Published`
and hand-patched to stay consistent — derivation cached where it could be computed.

**Direction.** Lift the admin CRUD members into their own module first — they have no reader outside
the admin screens. Then let read-only derivations compute rather than cache-and-patch. Separately,
decoding a question should not depend on ambient auth state: pass the current user in, so decode tests
stop requiring a configured Firebase.

**Deletion test.** Splitting moderation concentrates. Splitting the answer cluster only concentrates
*after* AD-2 collapses the five save entry points — do it in that order or the complexity moves
rather than shrinks.

**Open questions for grilling.** Does the admin module share the listener lifecycle or own its own?
Are the cached derivations load-bearing for scroll performance (see
`Documentation/PERFORMANCE_PASS_PLAN.md` and `Tests/HotPathBenchmarkTests.swift` — re-run the
benchmarks before removing any cache).

## AD-5 · Put a seam on the share-link service — LANDED

**Status:** Landed 2026-09-08. Seam and in-memory adapter in `83e54f8` (PR #27), ADR in `18f7498`
(`docs/adr/0009`); model migration onto the seam in `7d61a86` (issue #23); `UserDefaults` cache
deletion in `9c24a65` (issue #24); recipient-cap dedupe in `163545c`/`3e278de` (issue #25, PR #38).
Closed out by issue #26: no remaining `guard let service else` in `SharedQuestionListStore`, no
`UserDefaults` accepted-share cache reference outside history, and one definition of the recipient
cap (`QuestionListShare.defaultRecipientCap`).
**Strength:** Strong. **Dependency category:** ports & adapters.

**Landed on `main`.** `83e54f8` (PR #27) added `QuestionListShareServicing`, the live adapter
conformance, and `InMemoryQuestionListShareService`. `18f7498` recorded the ADR (`docs/adr/0009`).
Three previously separate branches (`worktree-ticket-23-share-servicing`, `fix/mainactor-share-service`,
`worktree-ad5-2-answer-snapshot-immutability`) were combined, reviewed, and merged as
`feat/ad5-share-servicing-integration`: `SharedQuestionListModel` moved onto the non-optional
`QuestionListShareServicing` seam and was renamed `SharedQuestionListStore` (issue #23);
`InMemoryQuestionListShareService` is `@MainActor`-isolated; the answer-snapshot-immutability assertion
landed (issue #22); and the `UserDefaults` accepted-share cache was deleted from the model (issue #24,
closed as part of this merge). Three review rounds on the combined branch also caught and fixed a
live-path regression (a placeholder owner name briefly leaking into the share sheet) and an adapter
identity-rebinding bug, neither requested by any ticket but both real defects introduced while unifying
the live and fixture code paths.

**Closed.** The recipient cap (25) that was duplicated across `QuestionListShare.swift`'s
Firestore-decode default, `InMemoryQuestionListShareService`'s default, and two lines of user-visible
copy in `SharedQuestionListViews.swift` now reads from the single `QuestionListShare.defaultRecipientCap`
literal everywhere on the client (issue #25, `163545c`/`3e278de`). Issue #26's closeout checklist ran
clean: `SharedQuestionListStore.swift` (the file `SharedQuestionListModel.swift` was renamed to) has no
`guard let service else`, no `UserDefaults` reference to the old cache remains outside git history, and
`grep` finds exactly one `defaultRecipientCap = 25`.

**Files (historical — as they stood when this entry opened)**

- `TTB/Services/QuestionListShareService.swift:7` — `actor QuestionListShareService`, no interface
- `TTB/Models/SharedQuestionListModel.swift` — optional service plus a `guard let service else` fixture lifecycle across `createShare`, `acceptShare`, `disableLink`, `regenerateLink`, `revoke` (~180 lines whose only callers are tests and harness roots)
- `TTB/Models/SharedQuestionListModel.swift:23, 37-42, 69, 616-650` — a `UserDefaults` cache of accepted share IDs
- `TTB/Services/QuestionListShareService.swift:114-139` — the recipients collection-group listener that already answers the same question; index at `firestore.indexes.json:31-46`
- Counterexample to copy: `TTB/Services/ContentReleaseService.swift:52-78` + `Tests/ContentReleaseClientFlowTests.swift`
- Recipient cap duplicated: `functions/questionListShares.js:5` (authoritative) vs `TTB/Models/QuestionListShare.swift:75`, and as English prose at `TTB/Views/Main/SharedQuestionListViews.swift:194, 727`
- `TTB/Models/SharedQuestionListModel.swift` was renamed to `TTB/Models/SharedQuestionListStore.swift` in `11f80ce`; all references above resolve there now.

**Problem.** Because the service is a concrete actor with no interface, the model carries a second
implementation of the share-link lifecycle so it can be tested — and
`Tests/QuestionListShareTests.swift:199-296` exercises that shadow path, not the real one. Two
independent sources of truth exist for "am I a recipient" (the `UserDefaults` cache and the listener),
and the recipient cap of 25 is encoded in four client places including twice in user-visible copy,
while the share document already carries `recipientCap`.

**Direction.** Extract a `QuestionListShareServicing` interface exactly as `ContentReleaseServicing`
already does one directory over, with a live adapter and an in-memory adapter — two adapters, so the
seam is real. Delete the fixture branches; the existing tests then test the real path. Delete the
`UserDefaults` cache (cost: a cold-start flash) and read the cap from the share document.

**Deletion test.** Concentrates on all three counts.

**ADR check.** Consistent with `docs/adr/0001-question-list-sharing-links-and-snapshots.md` — this
changes where the lifecycle is implemented on the client, not the claim/snapshot semantics.

**Open questions for grilling.** Does the interface expose callables one-for-one, or fewer, wider
operations? Is the cold-start flash acceptable, or does the pre-listener state need a different fix?

**Note.** No test anywhere asserts snapshot immutability — the property `CONTEXT.md` states most
explicitly ("Later answer edits do not change an existing snapshot"). It currently holds only because
no mutator happens to write `ownerAnswerSnapshots` after creation. Worth an assertion while in here.

## AD-6 · Name the answer-snapshot comparison

**Status:** Open.
**Strength:** Worth exploring. **Dependency category:** in-process.

**Files**

- `TTB/Views/Main/SharedQuestionListViews.swift` — 1220 lines, 13 types, 6 screens
- `:855-867` (recipient: answer snapshot vs live answers) and `:1008-1009` (owner: answer snapshot vs reply snapshot) — the two meanings, chosen by which closures the call site passes
- `:957-1027` — `SharedQuestionListComparisonList` takes an environment object plus 6 parameters and has 2 inits
- `:1030` — `SharedQuestionListComparisonView` is dead (no references in `TTB/`, `Tests/`, `TTBUITests/`), including an orphaned read-marking side effect
- `:447-458, :764-766` — recipient identity resolved by array scan on every `body` evaluation
- `TTB/Models/QuestionListShare.swift:173-177` — `AcceptedQuestionListShare` is a two-field tuple, not the recipient's view

**Problem.** The domain's central asymmetry — an immutable **answer snapshot** on one side, live
answers or a **reply snapshot** on the other — has no name in code. Nothing owns "the recipient's view
of a shared question list"; the state is assembled inside views, and what a comparison *means* lives
in two call sites.

**Direction.** A module that produces the comparison as a value, one method per role (owner,
recipient), so both screens render the same type. Split the file by screen while in there.

**Deletion test.** Concentrates — the pairing rule and the snapshot-vs-live distinction get one home.

**Domain-model side effect.** If this lands, add the comparison term to `CONTEXT.md`: the glossary
names *Answer Snapshot* and *Reply Snapshot* but not the comparison between them, which is the thing
both screens exist to render. Run `/domain-modeling` for the term rather than inventing one here.

## AD-7 · One notice seam

**Status:** Open.
**Strength:** Speculative. **Dependency category:** in-process.

**Files**

- `TTB/Models/QuestionModel.swift:28` — `error` is the only externally-writable published property; views write localized strings into it (e.g. `QuestionCardExpandedView.swift:1155`, duplicating `QuestionModel.swift:600-602`)
- The same `.alert` + `Binding(get:set:)` block in `HomeView`, `CategoryQuestionsView`, `AnswersView`, `MostAnsweredView`, `FavoritesView`
- `TTB/Models/ErrorState.swift` — the established pattern in the auth screens, unused by the question core
- `TTB/Views/Components/AppToast.swift:145-147` — `ToastCenterKey.defaultValue = ToastCenter()`: a hostless default, so a toast posted where no host is installed vanishes silently (including in harness paths that exist to test toasts)

**Problem.** Three user-notice channels coexist with nothing recording which to use for a new
failure, one of them silently swallows its input, and failure copy is duplicated in both languages
across model and view.

**Direction.** One notice interface carrying severity, presented as alert or toast by the host;
`error` becomes read-only with writes routed through it; drop the silent default on the environment
key so a missing host fails loudly.

**Deletion test.** Concentrates, but the gain is modest and the reach is wide.

**Why speculative.** `ToastCenter` is already well-factored and the alert duplication is cheap to
live with. Take this only if guest-milestone and shared-list toast work continues — AD-1 through AD-3
touch many of the same files and make this cheaper afterwards.

---

## Standalone fixes — no design decision needed

### FIX-1 · `#if DEBUG` gaps ship test doubles in release — FIXED

> **Status: fixed.** Nine harness files are now guarded, and the `*ForTesting` mutators on `AIModel`
> are gated along with the two preview providers that call them. Verified against a Release build:
> `UITestAuthProvider`, `UITestAccountDeletionService` and the trio mock services appear zero times in
> the release binary's symbols and strings, while a control symbol still resolves. Debug behaviour is
> unchanged — the harness-driven UI tests still pass.

The app target is a synchronized folder over `TTB/` with only four membership exceptions
(`TTB.xcodeproj/project.pbxproj:44-58`), and `TTB/UITestSupport/` is not one of them. Only
`UITestHomeRootView.swift` and `UITestProfileRootView.swift` carry a top-level `#if DEBUG`. So
`TTB/UITestSupport/UITestAuthMocks.swift` compiles into release builds — including an auth provider
whose `signIn(withEmail:password:)` accepts any password (`:38-40`) and a no-op account-deletion
service (`:115`). Only the *dispatch* is guarded (`TTB/App/TTBApp.swift:55`), not the types.

Same shape at `TTB/Models/AIModel.swift:387-405`: five `*ForTesting` mutators with no `#if DEBUG`,
where the equivalents in `QuestionModel.swift:324`, `QuestionListModel.swift:179` and
`SharedQuestionListModel.swift:353` *are* gated. The policy exists; it is applied per-file.

Fix: one `#if DEBUG` per file, plus a decision on whether harness code belongs in the app target at
all (which AD-3 would settle). Do this before any deepening work.

**Remediation applied.** A top-level `#if DEBUG` now wraps `UITestSharedQuestionListRootView`,
`UITestAIRootView`, `UITestMostAnsweredRootView`, `UITestCategoryQuestionsRootView`,
`UITestSharedQuestionRootView`, `UITestCategoryQuestionsFixture`, `UITestHomeFixture`,
`UITestAuthMocks` and `MockTrioServices`; the now-redundant inner guard in
`UITestSharedQuestionListRootView.refreshOwnedListSnapshotsForShareDetailHarness` is gone.
`AIModel`'s five `*ForTesting` mutators are gated, which required gating
`AIHistoryView_Previews` and `AIQueryInputView_Previews` as well — `PreviewProvider` bodies compile in
Release, and those two were the only non-harness callers.

Two files are deliberately left ungated because production code reads them:
`UITestLaunchOptions` (`HomeView.swift:28`, `QuestionCardExpandedView.swift:227`,
`QuestionListsView.swift:426`) and `UITestAuthContext` (`AIView`). Those call sites are exactly the
leaks AD-3 would remove; until then, gating either file breaks the Release build.

This closes the shipping risk, not the underlying question — the harness layer is still in the app
target, and adding a tenth harness file still defaults to shipped. AD-3 is the structural fix.

### FIX-2 · Disabling a share link breaks recipient re-entry — FIXED

> **Status: fixed.** Both callables now resolve already-accepted before applying the claimable gate,
> and the bypass additionally requires `share.status === "active"` so a half-completed revocation
> cannot read as valid re-entry. Three tests cover it: re-entry survives a disable, revocation still
> withdraws access, and a revoked share with a stale `accepted` recipient document is rejected.
> `functions` suite: 88 passing.

`functions/questionListShares.js:59` throws `failed-precondition` from
`previewQuestionListShare` before computing `isAccepted` at `:63-67`. `acceptQuestionListShare` has
the same ordering, so its idempotent early return at `:116` sits behind the gate at `:107`. An
existing **recipient** who reopens a **share link** after the owner disables it therefore gets "not
accepting recipients" — `TTB/Views/Main/SharedQuestionListViews.swift:126-133` surfaces it as an error
and never reaches the already-accepted re-route.

`CONTEXT.md` defines a share link as granting claim access "until the link is disabled", i.e.
disabling should stop new claims, not re-entry. Fix: compute `isAccepted` first and return the
accepted payload before the claimable check, on both callables. No test on either side covers this —
the client tests only run the fixture branch (see AD-5), and
`functions/questionListShares.test.js` has no case for it. Add one.

**Remediation applied.** The reordering landed on both `previewQuestionListShare` and
`acceptQuestionListShare`. One addition beyond the description above: the already-accepted bypass also
requires `share.status === "active"`. `revokeShareRef` updates the share document and *then* batches
recipient statuses in a separate write, so a failed batch leaves a revoked share whose recipient
documents still say `accepted`; without the status check that inconsistent state would grant re-entry
to a revoked share. `isAccepted` in the preview payload is computed the same way, so the response and
the gate cannot disagree — which matters because the client re-routes on that flag
(`SharedQuestionListViews.swift:128`).

The client needed no change. Note that the Firestore rule for recipient share reads already requires
`resource.data.status == 'active'`, so the half-revoked case was defended one layer down; the callable
should not have granted it in the first place.

### FIX-3 · Guest favorites never migrate on upgrade — FIXED AND DEPLOYED

> **Status: fixed and deployed.** Migration now calls the `addQuestionFavorites` callable instead of
> writing to Firestore from the client. The callable is live in `europe-west1`, confirmed with
> `firebase functions:list` on 2026-08-01, so the fix is in effect.

Found while grilling AD-1, not by the original survey.

`GuestFavoriteModel.firestoreMigrationWriter` wrote `favoriteUserIds: arrayUnion([userId])` straight
to `/questions/{questionId}` in a client batch. `firestore.rules` allows a non-admin update to that
path only when `affectedKeys().hasOnly(['creatorUsername'])` on their own `userCreated` question, so
**every migration was rejected**. The caller swallows the failure to allow a retry
(`AppEnvironmentRootView.swift:172`), so nothing surfaced.

User-visible effect: a guest with favorites upgrades to a permanent account and their favorites
disappear. The ids survive in `UserDefaults`, but once `isAnonymous` is false every screen reads the
account path, which is empty. The guest funnel's own conversion step silently discarded what it was
converting.

Why the tests didn't catch it: `Tests/GuestFavoriteModelTests.swift:159-171` injects a fake
`migrationWriter`, so 11 green tests cover the orchestration and never touch the write path. The
real writer had no coverage at all — it was the only Firestore write in the app that no test and no
rule check ever exercised.

**Remediation applied.**

- `functions/questionMutations.js` gains `addQuestionFavorites`: permanent accounts only, one
  transaction, idempotent (a question the caller already favorited is counted, not rewritten), and
  it skips missing or unavailable questions instead of failing the batch — a guest may have
  favorited a community question that was unapproved since, and that must not strand the rest.
  Returns `{ added, alreadyFavorite, unavailable, unavailableQuestionIds }`; the per-question list
  lets the client retain exactly the favorites the account did not accept.
- Five tests in `functions/questionMutations.test.js` cover the happy path, idempotency on retry,
  skipping, the permanent-account gate, and id-list validation. Suite: 93 passing.
- `GuestFavoriteModel.callableMigrationWriter` replaces the batch write. The `userId` parameter is
  now unused — the callable takes the uid from its own auth context, which is the only uid it will
  ever write.

**Deployed.** `addQuestionFavorites` is live as a v2 callable in `europe-west1`. Verified on
2026-08-01 with `firebase functions:list`. The status board and this section disagreed until then;
the board was right.

**Rollout requirement for the per-question response hardening:** deploy and verify the Functions
change before releasing the matching client. The already-deployed revision returns only the three
counts above, so the client treats a missing or malformed `unavailableQuestionIds` as a failed
migration and keeps every device-held id for a retry. It must never interpret an older response as
proof that every favorite migrated; that was the same silent-loss failure this fix exists to prevent.

**Superseded by AD-1 commit 3**, which moves this call behind `FavoriteStore`'s `FavoriteServicing`
adapter and deletes `MigrationWriter` and its injection point — the fake service becomes the test
seam, so the second injection stops earning its keep. The client-side shape here is deliberately
minimal so it can ship before that refactor.

### FIX-4 · Callables accept requests with no app attestation — FIXED AND DEPLOYED

**Status:** Fixed 2026-07-31 in `11ec82c` (the daily quota module), `065bd95` (App Check enforcement
and the rules), `74d5c63` (the client seam). Both console steps ran on 2026-08-01, and the callable
log confirms them: `"app":"VALID"` on `generatetrioquestionsuggestions` at `2026-08-01T20:40:15Z`,
against `"app":"MISSING"` on every line before it.
**Deployed on all six paid callables**, confirmed on 2026-08-01 by reading each one's last successful
`UpdateFunction` audit record rather than by trusting the CLI summary. The last two to land were
`askAIQuestion` at `21:48:22Z` and `generateQuestionPrompt` at `21:51:19Z`, after the deploy fight
recorded below.
Decisions and consequences: `docs/adr/0006-app-check-and-server-owned-ai-quota.md`.
Gates: 109 functions tests, 196 unit, 28 UI (one keyboard-focus flake in
`testQuickSuggestionPrefersFirstEmptySlotOverFocusedSlot`, passing on its own), Release build clean.
Release binary checked with `strings`: the debug-branch log line and every harness argument are absent
from it, so nothing this change added ships in release.
**Still open, and cheap:** no AI callable has been invoked since the last four deployed, so the
`"app":"VALID"` line above covers `generateTrioQuestionSuggestions` only. Use each of the six AI
features once from a debug build and read the verification line for each. That is the difference
between "the enforcing code is deployed" and "enforcement demonstrably accepts our own app", and
this document has already been wrong once about exactly that kind of gap (see FIX-3).

> **What shipped.** `enforceAppCheck: true` on `AI_FUNCTION_OPTIONS`, so the six paid callables reject
> any caller that does not attest, and the other 24 are untouched. `functions/aiUsageLimit.js` holds a
> server-side daily quota per uid, per group, in a transaction on `aiUsageDaily/{uid}` — a document no
> client may read or write. `aiCallable` is the only way `AI_FUNCTION_OPTIONS` reaches `onCall`, and a
> test fails if a seventh AI callable skips it. On the client, `AppCheckPolicy` maps a launch context
> to one of three providers and `AppCheckInstaller` installs it before `FirebaseApp.configure()`; the
> debug factory is inside `#if DEBUG` from the first commit, since FIX-1 was that shape.
>
> **This entry's central claim was wrong, and in the reassuring direction.** It said the per-user daily
> limit was the remaining brake, so abuse costs would scale with the number of accounts an attacker
> creates. There was no server-side brake. `requireAuthenticated` checked for a uid and nothing more;
> the 20-a-day limit lived in `AIUsageStats` and `TrioPromptModel`, and the counter it checked lived in
> `users/{uid}/aiUsage/stats`, which the client itself wrote under rules that validated field types
> rather than values. A direct callable invocation never touched the counter at all, and anonymous
> sign-in makes a uid free. The true figure was unbounded spend from one account that costs nothing.
> Found by grepping for the enforcement point before designing, which is the third time in three
> candidates that step has changed what got built.
>
> **The harness decision resolved itself.** The entry called it the one real decision and expected the
> debug provider to be needed for the UI suite. No UI test reaches an AI callable —
> `UITestAIRootView` injects `UITestTrioModelFactory`, and the harnesses run on local fixtures — so
> enforcement cannot break the suite. Harnesses install no provider at all. The debug provider exists
> for ordinary simulator work instead, which is what actually needed the console token.

**The deploy was the hard part, and it was a quota problem rather than a code problem.** Cloud Run
charges a per-project-per-region CPU quota as `cpu × maxInstances` summed over every service, and it
holds an old revision's reservation until the new revision passes its health check. Eleven services
never got past the first capped deploy in `70d8e48`, so they still sat on the v2 default of 100
instances and held roughly 1100 CPU between them. That left no room to start a replacement, which is
why retrying one function at a time failed too. Each failed attempt also leaves a dead revision
holding CPU, so rapid retries make it worse rather than better.

`72c2493` lowered the cap from 10 to 3. That cleared seven of the eleven at once, and after a pause
for revision collection the last four went one at a time. Eight deploy attempts in total.

**Two things to know before the next deploy.**

- Seven services still sit at `maxInstances: 10` — `addQuestionFavorites`, `disableQuestionListShare`,
  `generateTrioQuestionSuggestions`, `resolveUsername`, `revokeQuestionListShare`,
  `sendTestContentReleaseNotification` and `suggestAnswerImages`. They run the current handler code;
  only their cap failed to drop. The region now reserves about 139 CPU, so one ordinary full deploy
  should finish the job.
- A regional quota increase for "Total CPU allocation, per project per region" in `europe-west1` is
  still worth requesting. Lowering the cap again would buy less than the quota costs: 3 instances is
  already ~240 concurrent requests per function.

**Read the audit records, not the CLI summary.** The CLI reports per-run outcomes, and across eight
runs the picture only came together by parsing each function's last successful `UpdateFunction`
record out of `firebase functions:log`. A first pass at that parse also produced a false negative on
`generateQuestionPrompt`, so check the request/response pair rather than a single line.

**No outage came out of any of this.** A failed update leaves the previous revision in service, so
all 30 functions kept answering throughout.

Found during a security sweep after AD-1, not by the original survey. The original entry follows.

**Evidence.** App Check is referenced nowhere in `TTB/`, `functions/` or the docs, and the runtime
confirms it: every callable invocation logs `{"verifications":{"auth":"VALID","app":"MISSING"}}`.

**What is actually at risk.** Not the API key in `TTB/GoogleService-Info.plist` — that ships inside
every copy of the app and is public by design. The exposure is that the 30 callables accept requests
from anything that can obtain a Firebase Auth token, with no evidence the caller is our app.
`firestore.rules` does not help here: it denies *client* writes, and these requests are authenticated
users invoking server code that writes on their behalf. That is fine for the favorites and sharing
callables, whose blast radius is the caller's own data. It is not fine for the six AI callables
(`askAIQuestion`, `suggestAIAnswers`, `suggestQuickAnswers`, `generateQuestionPrompt`,
`generateQuestionVariations`, `generateTrioQuestionSuggestions`), which spend money per call against a
paid provider. The only brake today is the per-user daily limit, keyed on the caller's own uid, so the
cost of abuse scales with the number of accounts somebody is willing to create.

**Direction.** Add the App Check SDK with App Attest on device, register the app in the console, then
**monitor before enforcing** — enforcement rejects any client that is not attesting, and turning it on
blind takes the app down for anyone on an older build.

**Do it now rather than later.** Staged enforcement is normally the slow part, because you have to wait
for old app versions to drain. There are no active users yet, so that cost is currently zero. It only
grows.

**The one real decision: the harnesses.** App Attest does not work in the simulator, so every UI test
would fail closed once enforcement is on. The standard answer is a debug provider with a registered
debug token, which means harness-only attestation code in the app target — exactly the shape FIX-1 had
to clean up, so it must be `#if DEBUG` from the first commit, and it is another argument for AD-3
moving the harness layer out of the app target entirely.

**Open questions for grilling.** Does enforcement go on per-callable (AI first, where the money is) or
all at once? Does the debug provider live behind the same seam as the other harness adapters, or is it
an app-delegate concern? Is there a monitoring period worth waiting through at all, given there are no
users to drain?

### FIX-5 · `aps-environment` is hard-coded to `development` — FIXED

**Status:** Fixed 2026-07-31. `TTB/TTB.entitlements` reads `$(APS_ENVIRONMENT)`, and the TTB target's
Debug and Release configurations in `TTB.xcodeproj/project.pbxproj` set it to `development` and
`production`. This is FIX-4's `APP_ATTEST_ENVIRONMENT` pattern applied to the key sitting next to it,
which FIX-4 recorded as untouched.
**Verified:** both configurations built, and the processed entitlements read with `plutil -p` on
`<derivedData>/Build/Intermediates.noindex/TTB.build/<Config>-iphonesimulator/TTB.build/TTB.app-Simulated.xcent`
— `development` in Debug, `production` in Release, with `appattest-environment` tracking alongside it.
Simulator only; see the caveat below.

**Evidence.** The entitlement was the literal string `development` in both configurations, so a
TestFlight or App Store build registered against the APNs sandbox. A production push to a sandbox
token fails with `BadDeviceToken`, which names the token rather than the build, so the symptom does
not point at the cause. FCM sits in front of APNs here
(`docs/adr/0003-content-update-notifications-use-fcm.md`), and that does not change the failure —
FCM chooses the APNs environment from the token the app registered.

**Why a build setting rather than two entitlements files.** One file with a variable keeps the two
environment-dependent keys, `aps-environment` and `appattest-environment`, in one place and reading
the same way. Two files would have to stay in sync on the associated-domains list as well, which has
nothing to do with the configuration.

**The caveat, and it is not verified.** `aps-environment` is granted by the provisioning profile, and
a development profile grants only `development`. A **Release build signed with a development
identity** — which the Release configuration's `CODE_SIGN_IDENTITY = "Apple Development"` suggests
happens — now requests `production` and can fail to sign against such a profile. An archive picks a
distribution profile and is the case this fix is for. Simulator builds sign ad-hoc and never check a
profile, so the verification above cannot see this at all. Confirm on device before the next archive.

**Nothing else read the old literal.** No Swift file, `.xcconfig` file or `.plist` file mentions
`aps-environment` or `APS_ENVIRONMENT`, so no code assumed the sandbox.

Found in the "Not claimed" list of `docs/adr/0006-app-check-and-server-owned-ai-quota.md`, not by the
original survey — FIX-4 named it while fixing the key beside it and deliberately left it alone.

### FIX-6 · Three views build `BadgeModel` with no guard — FIXED

> **Status: fixed.** `f24ca60`, `387adf3`, `1a3a625`, `73414df`, `c520ce7`, `8ba1b01`
> ([bckizildemir/TTB#18](https://github.com/bckizildemir/TTB/issues/18)). `BadgeModel`'s Firestore
> surface sits behind `BadgeStoring`, with `LiveBadgeStore` and a `NoOpBadgeStore` fixture.
> `AppEnvironment` owns one `badgeModel` — `live()` wires the live store, `uiTest()` wires the
> no-op one — and installs it as an environment object alongside the other AD-3 models. All four
> views (`HomeView`, `ProfileView`, `AnswersContentView`, `MostAnsweredView`) read it from the
> environment; none constructs its own. `HomeView`'s `UITestLaunchOptions` guard is retired.
> `testAHarnessEnvironmentBadgeStoreTouchesNoFirestore` pins that the store behind
> `AppEnvironment.uiTest()`'s `badgeModel` never registers a live listener; `HarnessLayerIsolationTests`
> no longer lists `HomeView` as a launch-options reader. `8ba1b01` closed a follow-up bug where the
> transaction closure crossed `@MainActor` isolation unseen. Full suite green: 308 tests, 0 failures.

Found by AD-3's verification pass, which is also why it was filed separately rather than folded into
it.

`HomeView.swift:28` consults `UITestLaunchOptions.shouldSkipFirebaseConfiguration` before it builds a
`BadgeModel`, and AD-3 listed that as a launch-argument leak. The larger fact is that the guard covers
one construction site of four. These three consult nothing:

- `TTB/Views/Main/ProfileView.swift:612` — `@StateObject private var badgeModel = BadgeModel()`
- `TTB/Views/Main/AnswersView.swift:6` — the same, in `AnswersContentView`
- `TTB/Views/Main/MostAnsweredView.swift:403` — the no-argument `init`, which is the one `MainTabView`
  calls

`BadgeModel` constructs `Firestore.firestore()` at `:16` and opens a user listener at `:368`. So
`UITestProfileRootView` renders `ProfileView` and opens a live badge listener against the real project,
and so does every harness that reaches the Best-Of tab. `CategoryQuestionsView.swift:119` also builds
one but is a `PreviewProvider` and does not count.

Note that the guard was never about an unconfigured Firebase — see AD-3's correction 6. What it
prevented was network traffic, and it prevents it in one place out of four.

**Direction.** A port over `BadgeModel`'s Firestore surface — six operations — with a live adapter and
a no-op fixture, then all four sites take the instance from `AppEnvironment` the way AD-3's three
service slots do. The two `@StateObject` sites are the awkward part: `@StateObject` needs a concrete
`ObservableObject`, so the injection point has to be inside `BadgeModel` rather than a protocol in
front of it.

**Why not in AD-3.** Roughly 150 lines of new port code inside a change that was already rewriting
seven harness roots, and this repo's own history says an entry that grows past its file list gets
corrected later. `docs/adr/0008` records the deferral.

---

## Patterns already in this repo worth copying

Findings are not all negative; these are the shapes the candidates above are trying to reach.

- `TTB/Utilities/AppDeepLinkRouter.swift:54-98` — pure static parsing, separate published navigation
  state, no side effects; tested directly in `Tests/QuestionListShareTests.swift:94-143` with no
  harness. One wart: the allowed hosts are hardcoded at `:88-90` instead of `AppConfig`.
- `TTB/Models/AuthModelDependencies.swift:112-128` — a small dependencies value with a `.live`
  factory and a convenience init. The best seam in the repo, and the only one of its kind; the other
  models grew ad-hoc `local*:` inits and suppression booleans instead.
- `TTB/Services/ContentReleaseService.swift:52-78` — interface + adapters, which is why
  `Tests/ContentReleaseClientFlowTests.swift` can assert real view-model behaviour including failure
  paths. This is the template for AD-5.
- `TTB/Utilities/TodaysQuestionSelector.swift`, `QuestionAnswerDeletionReducer`,
  `GuestCapabilityPolicy` — rules extracted to where they can be tested without Firebase. AD-1 and
  AD-2 are asking for the same treatment on favorites resolution and answer saving.

## Terms that may enter `CONTEXT.md`

**Settled** — AD-1's and AD-2's terms were added while designing their modules and then challenged in a
`/domain-modeling` pass on 2026-07-31. What that pass changed is worth keeping, because in three of six
cases the wording agreed during design did not survive:

- **Favorite** — lost its closing sentence, "one module owns favorite state for both cases". True, but a
  fact about our code. The constraint lives in AD-1's entry and in `docs/adr/0005`, which is where a
  reviewer looks; a glossary that starts recording module boundaries stops being a glossary.
- **Guest Favorite** — gained the durability guarantee. The device keeps its copy until the account has
  accepted it, so a failed migration loses nothing. That is the property FIX-3 silently violated for
  months, and the entry did not state it.
- **Favorite Milestone** — new. `GuestFavoriteModel` has two thresholds and the glossary named one: the
  soft reminder at 3 is a distinct thing a guest experiences from the upgrade prompt at the cap, it is
  a named type in code, and it had no term. Conflating the two is what the glossary exists to prevent.
- **Answer Draft** — kept, reduced to the domain rule: answers compare equal ignoring surrounding space.
- **Answer Slot** — kept, but the four image states were cut. Enumerating `SlotImage`'s cases in prose
  was the Swift enum in disguise. The concept itself survived a scenario check: three fixed ordinal
  positions, any of which may be empty, is domain truth rather than padding — `answerStats` and the UI
  both depend on it.
- **Normalized Answer** — proposed and **rejected**. It described a storage representation ("the shape
  it is stored and compared in", "written to the backend") and existed because the code needed a type.
  Nothing a user or product owner does produces one. Its substance was a rule, not an entity, and that
  rule moved into **Answer Draft**. `NormalizedAnswer` keeps its name in code.

**Still pending**

- AD-6 — a name for the owner/recipient comparison (see its entry)

Add terms via `/domain-modeling` when the design settles, not in advance — and challenge them after,
since a term agreed while designing its own module tends to describe the module.

## Picking one up

Suggested route for an agent or a fresh session:

1. Read `CONTEXT.md` for the domain language and `docs/adr/` for decisions already made.
2. Load the `/codebase-design` skill for the vocabulary, then re-verify the candidate's citations —
   line numbers drift.
3. Run `/grilling` (or `/grill-with-docs`) on the chosen candidate to settle constraints, seam
   placement, and what sits behind it. Do not skip to implementation: none of these entries specifies
   an interface, on purpose.
4. If the interface is non-obvious, use `/codebase-design`'s design-it-twice pattern before choosing.
5. Build with `/tdd` — for AD-1, AD-2 and AD-5 the point of the refactor is that the rule becomes
   testable through one interface, so the test comes first or the deepening isn't verified.
6. Close out with `/code-review` and record any rejection reason as an ADR.

`FIX-1` and `FIX-2` need none of this — they are straight fixes with tests.

Verification gates before any of this is called done:

```bash
xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' test
```

```bash
cd functions && npm test
```
