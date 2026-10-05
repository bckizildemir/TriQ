# TTB memory & performance pass — changelog

Findings, priorities and the measurement method are in
[PERFORMANCE_PASS_PLAN.md](PERFORMANCE_PASS_PLAN.md).

## 2026-07-27 — Batches 1–5

Environment: iPhone 12 simulator, Debug configuration, 1,000-question synthetic corpus via
`Tests/HotPathBenchmarkTests.swift`.

**A measurement caveat that changes how to read these numbers.** Absolute timings on this machine
drifted badly over the session — the same unchanged benchmark measured 16 ms early on and 35 ms hours
later, after the machine had been running builds. Comparing an early "before" run against a later
"after" run is therefore not sound. The paired benchmarks below reimplement the pre-optimization
algorithm next to the current one so **both are measured in the same process**, and the ratio is the
number to trust.

### Measured — paired, same process

| Benchmark | Before | After | Change |
|---|---|---|---|
| `TodaysQuestionSelector.select` — 1,000 questions | 131 ms | 38 ms | **3.4× faster** |
| `AppLocalization.preferredLanguageCodes` × 1,000 | 11 ms | 5 ms | **2.2× faster** |
| Per-card favorite lookup — 40 cards × 3 reads | 2 ms | <1 ms | at timer floor |

`<1 ms` means below what `XCTest`'s wall-clock metric resolves, not zero.

### Measured — single-sided

| Benchmark | Value | Note |
|---|---|---|
| Favorite toggle fan-out — one star tap | 75 ms → <1 ms | see below |
| Question search filter — one keystroke | 22 ms → 16 ms | different machine states |
| `Question.text` × 1,000 | 16 ms → 11 ms | different machine states |
| `question(withID:)` × 1,000 | 2 ms | new benchmark, no before |
| `CategoryModel.activeCategories` × 100 | 3.0 → 4 ms | unchanged; within drift |

The favorite toggle is the headline and the one claim the drift cannot undermine. The 75 ms "before"
was measured on an idle machine and the "after" is below the timer floor in every machine state
tested — and structurally, the old toggle ran the whole today's-question selection plus four array
re-maps, a regroup and a corpus sort, while the new one patches elements in place. Since the selection
*alone* measures 38 ms in current conditions, the old toggle costs tens of milliseconds however it is
measured. That is several dropped frames per star tap, gone.

The two rows marked "different machine states" are real improvements whose exact ratio is not
trustworthy; treat them as directional.

### Measured — the app runs

Launched in the Home fixture harness on the simulator: idles at **~45 MB** physical footprint,
Home renders correctly under the new `LazyVStack` (verified by screenshot — section layout and
measured card heights intact).

### Measured — image decode size

`ImagePickerItemProviderTests` decodes the same 3024×4032 JPEG both ways and compares the resident
bitmap cost: the full decode is **>40 MB**, the downsampled decode **<6 MB** — over 8× smaller. The
same suite drives a real `NSItemProvider` (what `PHPickerResult.itemProvider` is) for both JPEG and
HEIC, confirming the new data-representation load path picks a usable type identifier and returns an
image within the ingestion cap.

### Reasoned, not measured — image memory in situ

The per-flow totals below extrapolate from that measurement; they are not observed footprint, because
driving the real photo flows end to end needs Firebase credentials.

| Path | Before | After |
|---|---|---|
| Picked profile photo held in `tempImage` | ~48 MB (12 MP) / ~195 MB (48 MP) | ~4 MB (1024 px cap) |
| Answer-image slots, 3 filled | up to ~144 MB | ~12 MB |
| `ImageService` in-memory cache ceiling | `countLimit = 60` only — GBs of bitmaps | 60 MB, now actually enforced |

### What changed

**Batch 1 — the localized-text pipeline**
- `AppLocalization.preferredLanguageCodes` now memoizes against the system preferred-language list
  ([AppLocalization.swift](../TTB/Utilities/AppLocalization.swift)). It was constructing a `Locale`
  per preferred language, doing string replacement and splitting, and de-duplicating with an O(n²)
  scan — on every access, and it is read transitively from every `Question.text` and
  `Category.displayName`. Keyed on the language list itself rather than a locale-change notification,
  so it cannot serve a stale answer.

**Batch 2 — whole-corpus re-derivation**
- `TodaysQuestionSelector` stores each SHA-256 rank as four big-endian words instead of a
  64-character hex string ([TodaysQuestionSelector.swift](../TTB/Utilities/TodaysQuestionSelector.swift)).
  The hex encoding cost 32 `String(format:)` calls per question and dominated the whole selection.
  It also ranks over indices rather than copying 1,000 `Question` values before sorting.
  `TodaysQuestionSelectorTests.testSelectionMatchesHexStringRanking` pins the new ordering against
  the hex implementation it replaced, over 120 questions × 5 days.
- `QuestionModel.setLocalFavoriteState` patches the derived collections in place instead of re-running
  the public-question derivation ([QuestionModel.swift](../TTB/Models/QuestionModel.swift)). A favorite
  flag cannot change which questions exist, how they group by category, or which are today's, so the
  four full array re-maps, the dictionary regroup, the corpus re-sort and the re-hash were all waste.

**Batch 3 — what a render pass actually pays**
- `QuestionModel` maintains an id→index map, funnelled through `replaceQuestions(_:)` so it cannot
  drift. `favoriteState(for:)` and `question(withID:)` are now dictionary lookups; the latter no
  longer concatenates all four caches into a fresh array per call.
- `QuestionCard.isFavorite` uses that lookup instead of scanning the corpus per card, per body
  evaluation ([QuestionCard.swift](../TTB/Views/Components/QuestionCard.swift)).
- `FavoriteModel` keeps a `Set` mirror of favorite ids for `favoriteState(questionId:)`.
- `QuestionListModel.isQuestionInAnyList` answers `isInQuestionList` without allocating the array of
  matching lists that `listsContaining(questionId:)` builds.
- `HomeView` uses `LazyVStack` ([HomeView.swift](../TTB/Views/Main/HomeView.swift)). It had ~23
  category sections in a plain `VStack`, each wrapping a page-style `TabView` that builds every card
  in its category up front — so all of them were materialized on first render and rebuilt on every
  invalidation.

**Batch 4 — image pipeline**
- New `DownsampledImageDecoder` ([DownsampledImageDecoder.swift](../TTB/Utilities/DownsampledImageDecoder.swift))
  decodes picked photo data straight to a 1024 px cap via ImageIO, so a full-resolution bitmap is
  never materialized. The cap is sized from what the app does with these photos: every upload is
  compressed to 800 px and the largest presentation is a full-screen `scaledToFit` viewer.
- `EditProfileView` downsamples at ingestion, off the main actor, instead of `UIImage(data:)`.
- `ImagePicker` loads the data representation and decodes it downsampled rather than asking the item
  provider for a `UIImage`, with a fallback to the object representation so an asset ImageIO cannot
  decode still picks.
- `ImageService.cacheImage` supplies a cost. `NSCache` only enforces `totalCostLimit` for entries
  with one, so the configured 60 MB limit was inert and `countLimit = 60` was the only bound. The
  upload path now also caches the resized image it actually uploaded rather than the larger original.
- `ImageService.loadProfileImage` decodes downsampled, which protects profile photos stored before
  the 800 px upload cap existed.
- `ProfileModel` writes the local profile cache off the main actor — it was a synchronous
  `jpegData` + `write(to:)` from a `@MainActor` method — and reads it back downsampled.

**Batch 5 — remaining derivation cleanups**
- `allQuestions` (a full corpus sort) is no longer read on hot paths: the guest-favorite preview and
  `FavoritesView` resolve ids through the new `questions(withIDs:)`; the question-list picker reads
  the already-newest-first cache; `AdminQuestionView` sorts only the questions that survive filtering
  instead of triggering four full sorts per body evaluation.
- `FavoritesView`, `AnswersView` and `MostAnsweredView` derive once per render and thread the result
  down, rather than reading the derivation for an `.isEmpty` check and again for the `ForEach`.
- `AnswersView.answeredQuestions` decorates in one pass; it previously read the answer record in the
  filter and twice more per sort comparison.
- `QuestionModel.mostAnsweredQuestions` counts filled slots once per question instead of inside the
  comparator.
- `ProfileModel` no longer fetches `users/{uid}` twice on load — `loadUserProfile()` and
  `loadStatistics()` were both reading the same document and were always called together.

### Reverted after measuring

- **`CategoryModel.activeCategories` decoration.** Hoisting `displayName` out of the sort comparator
  measured *slower* (3 ms → 16 ms per 100 calls): with the Batch 1 cache in place, `displayName` is
  cheap and only reached on the rare equal-`sortOrder` tie-break, so copying the decorated structs
  cost more than it saved. Reverted, with the measurement recorded in a comment so the next person
  does not repeat it.

### Left alone deliberately

- **`AnswerImageFullscreenView` and `FullProfilePhotoView`** legitimately want the largest image
  available — one on screen, detail is the point. Not routed through a smaller cap.
- **`ImageService.compressImage`** was already correct: it resizes before encoding once, rather than
  looping on JPEG quality. Only the constant was named.
- **`HomeView`'s outer `GeometryReader`** is greedy and imposes layout cost, but it feeds a real
  card-height clamp. Replacing it with `containerRelativeFrame` is a visual-risk change with no
  measured win.
- **`print()` calls** are all inside `#Preview` bodies.
- **`listsContaining(questionId:)`** is kept for callers that need the actual lists; only the
  yes/no reader was switched.

### Deferred

- **Unbounded Firestore listeners.** `setupSeededQuestionsListener` and `setupTrioQuestionsListener`
  subscribe to every seeded and every approved user-created question with no `limit`, so memory and
  Firestore read cost grow monotonically with the corpus. This is the one finding that will
  eventually undo the wins above, because every derivation here is linear in corpus size. Fixing it
  means pagination or per-category subscriptions — a decision about what Home shows, not a perf
  tweak. **Needs a product/architecture decision.**
- **`Question: Equatable`.** Would let SwiftUI skip more re-renders, but it changes view-identity
  semantics app-wide and wants its own measured change.

### Verification

- Full unit suite (`TTBTests`) green: 168 tests, 0 failures.
- Zero new compiler warnings in `TTB/` sources.
- Home renders correctly under the new `LazyVStack`, verified by screenshot in the fixture harness.

Two UI tests fail. Both were run down rather than assumed:

- `ProfileSheetPresentationUITests/testProfileSheetsStayPresented` — **pre-existing**. Reproduced on a
  clean `main` checkout.
- `AITrioComposerUITests/testTrioComposer_generateVariationAndPublish` — **flaky on `main`, not a
  regression from this pass.** This one is worth recording, because the evidence initially pointed the
  other way: it passed on `main` on the first try and then failed 6/6 on this branch, which looks
  exactly like a regression. Bisecting by reverting files in groups walked all the way back to
  batches 1–2 and then to a fully clean tree, where it still failed — so the tree was never the
  cause. Running it 3× on clean `main` settled it: **2 of 3 failed**. The test races a ~0.9 s window
  in which the success toast and the composer sheet must both be present (`AITrioComposerUITests.swift:22-30`),
  and it loses that race under load. Worth fixing as a test-stability issue, separately from this pass.

The general lesson: a single passing run on the base branch is not a baseline. Had the bisect stopped
one step early, this pass would have reverted correct, measured work to chase a pre-existing flake.

### Not verified

- No footprint measurement under a realistic question corpus or a real photo save/scroll flow: both
  need Firebase credentials and a seeded project. The decode-size reduction *is* measured; the
  per-flow totals extrapolate from it. The `NSCache` cost fix is a code-level correctness claim, not a
  measured reduction.
- The picker's load path is verified against a synthesized `NSItemProvider`, not against a real
  PhotoKit asset picked by hand. That covers the identifier selection and the decode, but not
  PhotoKit-specific quirks of a particular library asset.
- No Instruments Time Profiler or dropped-frame count on a real device. The derivation wins are
  micro-benchmarked, which is not the same as proven scroll smoothness.
- The `HomeView` `LazyVStack` change is verified as correct rendering, not as a measured render-time
  win — the fixture harness only has two sections.
- Benchmarks cannot run in the Release configuration at all: the unit target uses
  `@testable import TTB` and the models expose their test seams behind `#if DEBUG`. An earlier
  Debug-plus-`SWIFT_OPTIMIZATION_LEVEL=-O` baseline showed most costs roughly halving under
  optimization, while `TodaysQuestionSelector.select` barely moved (99 → 88 ms) because Foundation's
  `String(format:)` is not something the optimizer can improve — which is why that finding was worth
  fixing rather than dismissing as a Debug artifact.

---

## Addendum — AD-1 (FavoriteStore), 2026-07-31 — **corrected 2026-08-02**

`FavoriteStore` now owns favorite state, so the mechanism this pass tuned is gone rather than faster:
`QuestionModel.setLocalFavoriteState` patched the flag into six derived collections on every star tap,
and nothing reads that flag any more. The store's ladder puts pending writes and the backend snapshot
above the flag decoded onto a question, so a stale flag cannot surface.

> **The 2026-07-31 favorite numbers are withdrawn: they measured a signed-out store.** Both benchmarks
> built `FavoriteStore.previews`, which never receives `setIdentity`, so `identity` stayed
> `.signedOut`. On that identity `toggle(_:)` returns `.failed` from the first case of its `switch`
> before it touches any state, and `state(of:)` returns the `isFavorite` flag decoded onto the
> question. Neither call reached the precedence ladder, so neither number described the code it
> claimed to. Both benchmarks now drive the store to `.account` with a 200-favorite snapshot loaded
> (`makeAccountStore` in `Tests/HotPathBenchmarkTests.swift`).

Re-measured on the same 1,000-question corpus, Debug, iPhone 16 simulator (iOS 18.5), steady-state,
ignoring the first warm-up iteration:

| Benchmark | This pass | Withdrawn — signed out | **After AD-1 — account** |
|---|---|---|---|
| Per-card favorite lookup — 40 cards × 3 reads | <1 ms (timer floor) | ~0.05 ms | **~0.058 ms** |
| Favorite toggle fan-out — one star tap | <1 ms (from 75 ms) | ~0.16 ms | **~0.56 ms** |

**The toggle costs 3.5× what was published.** The withdrawn 0.16 ms was the signed-out guard plus
harness overhead. The 0.56 ms is the account path: one dictionary write, then a filter and sort of the
200-favorite list, plus the same `XCTestExpectation` and main-actor hop that awaiting an async method
from `measure` requires. It scales with the size of the favorites list, not with the corpus — that is
the property worth keeping, and it is why 200 favorites is the fixture rather than 1,000. Steady-state
relative standard deviation is ~8%; the reported 216% is the 17.9 ms first iteration.

**The per-card row barely moved, and that is a coincidence worth naming.** A `Set.contains` on
`snapshotIDs` costs about what the stored-property read cost, so the published 0.05 ms happened to
land near the truth while describing the wrong code path. Do not read the small delta as confirmation
that the old measurement was sound.

**The toggle row is still not a like-for-like comparison.** The old benchmark called
`setLocalFavoriteState` directly and measured the six-collection patch; no before-number was taken on
that implementation, and getting one needs a checkout of `82cc6f1^` and a full rebuild. The honest
claim stays narrower than a number: the fan-out no longer exists, because there is nothing left to fan
out to.

**The paired comparison is the trustworthy one, and it survives the correction.**
`testBenchmarkBaseline_PerCardFavoriteLookupByLinearScan` measures the pre-index scan at ~0.95 ms
against the ladder's ~0.058 ms in the same process — about **16× faster**, now measured against the
ladder rather than the seed rung. One caveat the ratio carries: both take `corpus.prefix(40)` as the
visible cards, so the baseline's `first(where:)` finds each card in the first 40 of 1,000 and
short-circuits early. The real scan is worse than the baseline shows, so 16× is a floor.

Unchanged by AD-1, re-recorded on 2026-08-02 in the same run and reproducing the 2026-07-31 figures:
today's-question selection ~11 ms (hex-ranking baseline ~36 ms), question search ~4 ms, text
resolution ~3 ms, question lookup by id ~0.64 ms, preferred language codes ~1.9 ms (uncached baseline
~3.9 ms), `activeCategories` ~1.5 ms.
