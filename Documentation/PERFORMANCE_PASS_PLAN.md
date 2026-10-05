# TTB memory & performance pass — plan

Date opened: 2026-07-27

## Method

Measure first, trace to root cause, then widen the search for the same shape. Every finding below
cites `file:line` and states its cost in concrete terms.

**Measurement vehicle.** `Tests/HotPathBenchmarkTests.swift` — micro-benchmarks over a synthetic
1,000-question corpus for the derivations that run on the home render, the favorite toggle, and
question search. Re-runnable:

```bash
xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 12' -only-testing:TTBTests/HotPathBenchmarkTests test
```

**What these numbers are and are not.** They measure CPU cost of pure derivations. They do not
measure footprint (derivation fixes will not move it) and they do not prove scroll smoothness.
Image findings are sized by arithmetic, which is labelled as such.

**Release-configuration caveat.** The unit target uses `@testable import TTB` and the models expose
their test seams behind `#if DEBUG`, so the suite cannot build in the Release configuration at all.
Benchmarks are therefore run twice: stock Debug, and Debug with `SWIFT_OPTIMIZATION_LEVEL=-O` as the
closest available stand-in for shipping optimization levels.

## Baseline (iPhone 12 simulator, 1,000-question corpus)

| Benchmark | Debug | Debug `-O` |
|---|---|---|
| `TodaysQuestionSelector.select` — 1,000 questions | 99 ms | 88 ms |
| Favorite toggle fan-out — one star tap | 75 ms | 54 ms |
| Question search filter — one keystroke | 22 ms | 9 ms |
| `Question.text` × 1,000 | 16 ms | 10 ms |
| `AppLocalization.preferredLanguageCodes` × 1,000 | 8.7 ms | 5 ms |
| `CategoryModel.activeCategories` × 100 | 3.0 ms | 1 ms |
| Per-card favorite lookup — 40 cards × 3 reads | 1.45 ms | 1 ms |

At 60 fps a frame is 16.7 ms. A 54–75 ms main-actor block on a star tap is ~4 dropped frames.

**These absolute numbers proved unreliable for before/after comparison.** Timings on this machine
drifted roughly 2× over the session as it warmed up under repeated builds, so the results in
[PERFORMANCE_PASS_CHANGELOG.md](PERFORMANCE_PASS_CHANGELOG.md) use paired benchmarks that measure the
old and new algorithm in the same process instead. Treat the table above as the initial triage that
ranked the findings, not as the result.

Worth noting which findings survive optimization. Most costs roughly halve under `-O`, but
`TodaysQuestionSelector.select` barely moves (99 → 88 ms) because it is dominated by Foundation
`String(format:)` calls that the optimizer cannot touch. That is a real shipping cost, not a Debug
artifact.

## The two root causes

**A — The localized-text pipeline re-runs per access.** `AppLocalization.preferredLanguageCodes`
([AppLocalization.swift:22](TTB/Utilities/AppLocalization.swift:22)) is a computed static that calls
`Locale.preferredLanguages`, constructs a `Locale` per entry, does string replacement and splitting,
and de-duplicates with an O(n²) `contains` scan — on **every** access. `Question.text`
([Question.swift:87](TTB/Models/Question.swift:87)) and `Category.displayName`
([Category.swift:46](TTB/Models/Category.swift:46)) are computed properties that each run the whole
pipeline. Those two are read per card body, per accessibility label, per search-filter item, and
twice per comparison inside `activeCategories`' sort comparator. Fixing the source makes every
downstream read cheap without touching a single call site.

**B — Whole-corpus re-derivation on every small state change.** A single favorite toggle
([QuestionModel.swift:246](TTB/Models/QuestionModel.swift:246)) re-maps four full arrays, regroups
into a dictionary, re-sorts the corpus, and re-runs today's-question selection — which SHA-256
hashes every question and formats each digest into a 64-character hex string via 32 `String(format:)`
calls per question ([TodaysQuestionSelector.swift:45](TTB/Utilities/TodaysQuestionSelector.swift:45)).
Then it republishes four `@Published` properties, invalidating every mounted screen.

## Findings

### P0 — highest impact ÷ effort

1. **`preferredLanguageCodes` recomputed per access.**
   [AppLocalization.swift:22](TTB/Utilities/AppLocalization.swift:22). 8.7 µs per call; called
   transitively from every `question.text` and `category.displayName`. Cache it, invalidate on
   `NSLocale.currentLocaleDidChangeNotification`.

2. **Today's-question ranking formats 32 hex bytes per question.**
   [TodaysQuestionSelector.swift:45-49](TTB/Utilities/TodaysQuestionSelector.swift:45). 1,000
   questions → 32,000 `String(format:)` calls, then a full sort comparing 64-character strings. 99 ms.
   Replace the hex-string rank with a byte-ordered comparable value — identical ordering, because
   lexicographic order over lowercase hex strings equals lexicographic order over the digest bytes.

3. **Favorite toggle re-runs the entire public-question derivation.**
   [QuestionModel.swift:240-265](TTB/Models/QuestionModel.swift:240). 75 ms per star tap. A favorite
   flag cannot change *which* questions are today's or *how* they group by category, so skip the
   re-selection and re-grouping and patch the already-derived arrays in place.

4. **`QuestionCard.isFavorite` scans the whole corpus per card.**
   [QuestionCard.swift:31](TTB/Views/Components/QuestionCard.swift:31) — `model.questions.first(where:)`,
   O(corpus) per card, read ~3× per card body. Back it with an id→index map.
   `FavoriteModel.favoriteState` ([FavoriteModel.swift:156](TTB/Models/FavoriteModel.swift:156)) has
   the same shape over `favoriteQuestions`.

5. **HomeView materializes all 23 category sections eagerly.**
   [HomeView.swift:43](TTB/Views/Main/HomeView.swift:43) uses `VStack` inside a `ScrollView`, so every
   `CategorySection` — each a page-style `TabView` holding every question in that category — is built
   on first render and rebuilt on every invalidation. `LazyVStack` is a one-word fix.

6. **Profile image holds a full-resolution bitmap to draw a 28 pt circle.**
   [EditProfileView.swift:110](TTB/Views/Main/EditProfileView.swift:110) decodes the picked photo at
   full resolution into `model.tempImage`; [ProfileModel.swift:248](TTB/Models/ProfileModel.swift:248)
   then assigns that same full-res image to `profileModel.profileImage`, which
   [HomeView.swift:189](TTB/Views/Main/HomeView.swift:189) renders into a 28×28 circle. Arithmetic: a
   12 MP photo is 4032 × 3024 × 4 = **~48 MB** resident (a 48 MP iPhone photo is ~195 MB) to draw the
   ~9 KB a 28 pt @3× circle needs. Downsample at ingestion.

7. **`ImageService`'s cache cost limit is never enforced, and it caches the original.**
   [ImageService.swift:54](TTB/Services/ImageService.swift:54) sets `totalCostLimit = 60 MB` but
   [ImageService.swift:147](TTB/Services/ImageService.swift:147) and
   [ImageService.swift:202](TTB/Services/ImageService.swift:202) call `setObject(_:forKey:)` with no
   cost, so only `countLimit = 60` applies — 60 full-resolution bitmaps is multiple GB. Line 202 also
   caches the *uncompressed original* rather than the 800 px version that was uploaded.

8. **Full-resolution JPEG encode + disk write on the main actor.**
   [ProfileModel.swift:269](TTB/Models/ProfileModel.swift:269) calls
   `LocalFileManager.saveImage` — synchronous `jpegData` + `write(to:)` — from a `@MainActor` method.
   Several hundred ms of hang on the profile Save button.

### P1 — real, smaller reach

9. **`allQuestions` sorts the corpus, then callers throw the order away.**
   [QuestionModel.swift:333](TTB/Models/QuestionModel.swift:333). Called to build id→question
   dictionaries at [AppEnvironmentRootView.swift:153](TTB/App/AppEnvironmentRootView.swift:153) and
   [FavoritesView.swift:55](TTB/Views/Main/FavoritesView.swift:55), where the sort is pure waste; and
   read 4× per body in [AdminQuestionView.swift:57,70,78](TTB/Views/Admin/AdminQuestionView.swift:57),
   twice per body in the question picker
   ([QuestionListsView.swift:634,638](TTB/Views/Main/QuestionListsView.swift:634)).

10. **Derivations read twice per body render.** `answeredQuestions`
    ([AnswersView.swift:15](TTB/Views/Main/AnswersView.swift:15) — filter over `myAnswers` plus a
    sort), `displayedFavoriteQuestions`
    ([FavoritesView.swift:53](TTB/Views/Main/FavoritesView.swift:53) — builds a dictionary of the
    whole corpus), `currentItems`
    ([MostAnsweredView.swift:493](TTB/Views/Main/MostAnsweredView.swift:493) — maps every item). Each
    is read once for an `.isEmpty` check and again for the `ForEach`.

11. **`mostAnsweredQuestions` recomputes sort keys per comparison.**
    [QuestionModel.swift:339](TTB/Models/QuestionModel.swift:339) — the comparator calls
    `myAnswers(for:).filter{...}.count` on both operands, so an O(n log n) sort does O(n log n) filter
    passes. Currently unused by any view; keep it correct and cheap or delete it.

12. **`question(withID:)` concatenates four arrays then linear-searches.**
    [QuestionModel.swift:353](TTB/Models/QuestionModel.swift:353). Called per question id when
    resolving a question list ([QuestionListModel.swift:83](TTB/Models/QuestionListModel.swift:83),
    [SharedQuestionListStore.swift:111](TTB/Models/SharedQuestionListStore.swift:111)) — a full
    corpus-sized allocation per list entry.

13. **`listsContaining` allocates an array to answer a yes/no question.**
    [QuestionListModel.swift:74](TTB/Models/QuestionListModel.swift:74), reached from
    `QuestionCard.isInQuestionList` which is read ~4× per card body.

14. **`ProfileModel` fetches the same user document twice on load.**
    [ProfileModel.swift:105](TTB/Models/ProfileModel.swift:105) and
    [ProfileModel.swift:140](TTB/Models/ProfileModel.swift:140) — `loadUserProfile()` and
    `loadStatistics()` each `getDocument()` on `users/{uid}`, and both are always called together.

15. **Answer-image slots hold up to three full-resolution bitmaps.**
    [QuestionCardExpandedView.swift:75](TTB/Views/Components/QuestionCardExpandedView.swift:75) —
    `@State private var images: [UIImage?]` filled by `ImagePicker`
    ([ImagePicker.swift:44](TTB/Views/Components/ImagePicker.swift:44)) at full resolution. ~48 MB ×
    3 while the sheet is open, to display previews and then upload at 800 px anyway.

### P2 — deliberately not changed in this pass

- **Unbounded Firestore listeners.** `setupSeededQuestionsListener`
  ([QuestionService.swift:531](TTB/Services/QuestionService.swift:531)) and
  `setupTrioQuestionsListener` ([QuestionService.swift:580](TTB/Services/QuestionService.swift:580))
  subscribe to every seeded and every approved user-created question with no `limit`. Cost grows
  monotonically with the seeded corpus, in memory *and* in Firestore reads. Fixing this means
  pagination or per-category subscriptions — an architecture and product decision about what Home
  shows, not a perf tweak. **Deferred, flagged for a design decision.**
- **`Question` is not `Equatable`.** SwiftUI falls back to reflective comparison for views holding a
  `Question`. Conforming it would let SwiftUI skip more re-renders, but it changes view-identity
  semantics app-wide and wants its own measured change. **Deferred.**
- **`HomeView`'s outer `GeometryReader`** ([HomeView.swift:38](TTB/Views/Main/HomeView.swift:38)) is
  greedy and imposes layout cost, but it feeds a real card-height clamp. Replacing it with
  `containerRelativeFrame` is a layout change with visual risk and no measured win. **Left alone.**
- **`AnswerImageFullscreenView`** legitimately wants full resolution — one image on screen, detail is
  the point. **Left on the full-size path deliberately.**
- **`ImageService.compressImage`'s 800 px cap** is already correct: it resizes before encoding once,
  rather than looping on JPEG quality. **No change needed.**
- **`print()` calls** are all inside `#Preview` bodies. **No change needed.**

## Batches

Each batch: build with zero new warnings, full unit suite green, benchmarks re-run, changelog entry
with before/after.

- **Batch 1 — localized-text pipeline (P0 #1).** The single widest-reach fix; everything downstream
  gets cheaper for free. Do it first so later measurements are taken against the corrected baseline.
- **Batch 2 — today's-question ranking and the favorite-toggle fan-out (P0 #2, #3).** #3 builds on
  #2's cheaper selection.
- **Batch 3 — per-card lookups and lazy Home (P0 #4, #5, P1 #13).** These are what a render pass
  actually pays.
- **Batch 4 — image pipeline (P0 #6, #7, #8, P1 #15).** Downsample at ingestion, then fix the cache
  and the main-actor write that consume it.
- **Batch 5 — remaining derivation cleanups (P1 #9, #10, #11, #12, #14).**
