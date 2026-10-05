# Swift 6 language mode + strict concurrency: measured assessment

**Date:** 3 October 2026 · base `main` @ `ca435bb` · measured in an isolated worktree
**Toolchain:** Apple Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27.0 (27A266a)
**Project:** `IPHONEOS_DEPLOYMENT_TARGET = 18.2`, `SWIFT_VERSION = 5.0` in all 6 build configurations
(3 targets × Debug/Release), `SWIFT_STRICT_CONCURRENCY` unset, no `SWIFT_UPCOMING_FEATURE_*` flags
set, no `SWIFT_DEFAULT_ACTOR_ISOLATION` set.
**Packages:** `firebase-ios-sdk` 11.7.0 and `Nuke` 12.9.0, pinned in the tracked `Package.resolved`.

Every number in this document comes from a build on 2026-10-03. No number is an estimate. The method
is in [Appendix A](#appendix-a--measurement-method). This is step 1 of the migration: measure and
record. No Swift file and no build setting changed on any branch.

The template is CatCareCalendar's (CCC) `docs/swift6-concurrency-assessment.md` (measured
2026-09-08, migration finished 2026-09-24). [Appendix B](#appendix-b--ccc-lessons-and-whether-they-held-here)
lists which CCC lessons held here and which did not.

---

## 1. Verdict

**Do it, warnings first, language mode last — the same shape as CCC. The work is about 10× CCC's.**
Measured 2026-10-03:

- Plain `complete` checking on the app target: **202 warnings in 40 of 181 files**, 0 errors, full
  coverage, build succeeds. CCC had 19 in 14.
- Swift 6 language mode on the app target: **build fails**, 22 errors from the 158 files it reached.
  That is a lower bound (section 2).
- UI tests: **718 warnings** under `complete`, all of one shape (XCUI is main-actor, XCTest methods are
  not). One build setting takes it to 56.
- Unit tests: **31 warnings in 8 files** under `complete`.
- Main-actor-by-default does **not** reduce the app count (202 → 202); it moves the cost into the
  service actors. `NonisolatedNonsendingByDefault` alone **fails the build** (26 errors in one file).
- No compiler crash, no `failed to produce diagnostic for expression`, no macro-expansion
  diagnostic, no diagnostic from a package or the platform SDK, in any of 13 builds.

**Moving to Swift 6 language mode does not need a higher minimum iOS.** No build in any stage
produced an availability diagnostic against iOS 18.2. One fix candidate below (`isolated deinit`)
may need iOS 18.4; section 3 says how to avoid it.

**The 22 `ObservableObject` types and the 5 `DispatchQueue` files are not the problem.** The
compiler flags nothing about `ObservableObject`, `@Published`, or `DispatchQueue` itself (0 of 202
diagnostics). 21 of the 22 classes are already `@MainActor`. What the compiler does flag in those
files is what they *call* (section 3.2).

---

## 2. Measured diagnostic counts

Counts are unique `file:line:col: kind: message` diagnostics whose path is inside the repository.
The generic simulator destination builds both `arm64` and `x86_64`; de-duplication by
`file:line:col:message` removes the second copy. "Coverage" is the number of the target's `.swift`
files that appear in a compile command in the log. The app target compiles all 181 files under
`TTB/` (the folder is a synchronized group; only `Info.plist` and `Secrets.xcconfig` are excluded).

### App target (measured 2026-10-03)

| Stage | Settings on the app target only | Errors | Warnings | Files | Coverage |
| --- | --- | --- | --- | --- | --- |
| A1 · Baseline | as-is | 0 | 12 | 5 | 181/181 · full |
| A2 · Targeted | `SWIFT_STRICT_CONCURRENCY = targeted` | 0 | 29 | 11 | 181/181 · full |
| A3 · Complete | `SWIFT_STRICT_CONCURRENCY = complete` | 0 | **202** | **40** | 181/181 · full |
| A3n · Complete + nonsending | A3 + `NonisolatedNonsendingByDefault` | **26** ‡ | 42 | 15 | 112/181 · partial |
| A3m · Complete + MainActor | A3 + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | 0 | **202** | **32** | 181/181 · full |
| A4 · Complete + MainActor + nonsending | A3 + both | 0 | **202** | **32** | 181/181 · full |
| A5 · Swift 6 mode | `SWIFT_VERSION = 6.0` | 22 | 4 | 11 | 158/181 · partial |
| A5b · Swift 6 + continue | A5 + `-continue-building-after-errors` | 37 | 9 | 16 | 135/181 · partial |

A3 was built a second time (A3r) to check that the count is reproducible: the two diagnostic lists
are identical, line for line.

A3m and A4 also produce identical diagnostic lists, line for line. **On top of
main-actor-by-default, `NonisolatedNonsendingByDefault` changes nothing here.**

‡ **`NonisolatedNonsendingByDefault` on its own fails the build, even in Swift 5 mode.** All 26
errors are in one file, `Services/InMemoryQuestionListShareService.swift` (a `#if DEBUG`
`@MainActor final class` that conforms to `QuestionListShareServicing`). Inside its `async` protocol
witnesses (lines 47–198), every read or write of the class's own main-actor state is reported as
"main actor-isolated … cannot be accessed from outside of the actor" — as errors, not warnings, at
`SWIFT_VERSION = 5.0`. The cause was not investigated further; it belongs to stage 5 and does not
block stages 0–4. A3n reached only 112 of 181 files, so its other counts are a lower bound.

**The baseline already has 12 warnings, 9 of them concurrency.** Swift 5 mode with minimal checking
still reports: the retroactive `Sendable` conformance on FirebaseAuth's `User` and the
`Sendable` struct that stores `Firestore`/`Functions`/`LocalFileManager`
(`Services/AccountDeletionOperations.swift`, 7), and the main-actor static `defaultFavoritesKey`
read from a nonisolated context (`Models/GuestFavoriteModel.swift:44`,
`UITestSupport/UITestGuestFavoriteSeed.swift:15`). The other 3 are not concurrency (2 unused `Task`
results in `App/WindowTopmostPresenter.swift`, 1 `weak` capture in `Models/BadgeModel.swift:358`).

**Stage A2 (`targeted`) is not worth a stop.** It reports 29: the baseline 12, plus 12
listener protocol-requirement warnings (category C), 4 "non-`Sendable` type … cannot exit main
actor-isolated context" warnings (category B), and 1 more `@preconcurrency` hint. It gives no safety that A3 does not, and it hides the 112
region-isolation warnings that are the bulk of the work.

**Stages A5 and A5b are lower bounds, and that is the finding — the same one CCC made.** In error mode
the module stops, so files behind a failed file never report. A5 reached 158 of 181 files.
`-continue-building-after-errors` made coverage *worse* (135), though it reported more errors (37).
Neither count is the size of the problem. Stage A3, at full coverage, is the only trustworthy total.

**Stage A4 does not beat A3 here.** In CCC, main-actor-by-default cut the count (19 → 15). In TTB it
does not: 202 → 202. It removes one category and creates another of the same size (section 3.4).

### Test targets (measured 2026-10-03)

Measured with `build-for-testing`, with the app target at baseline so it could not stop the build.
The unit test target has 49 files (36 reference `XCTestCase`, 5 `import Testing`); the UI test target
has 14 files, one `XCTestCase` subclass each.

| Stage | Settings on the test targets | Errors | Unit warnings (files) | UI warnings (files) | Coverage unit / UI |
| --- | --- | --- | --- | --- | --- |
| T1 · Baseline | as-is | 0 | 1 (1) | 0 | 49/49 · 14/14 |
| T2 · Complete, both | `SWIFT_STRICT_CONCURRENCY = complete` | 0 | **31** (8) | **718** (14) | 49/49 · 14/14 |
| T3 · Complete, UI also MainActor | T2 + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on UI tests only | 0 | 31 (8) | **56** (14) | 49/49 · 14/14 |
| T4 · Swift 6 mode, both | `SWIFT_VERSION = 6.0` | 13 | 12 (7) | — | 18/49 · 0/14 · partial |

**All 718 UI-test warnings are main-actor access from a nonisolated test method**: 250 calls to
main-actor methods (`tap()`, `typeText`, `launch()`, …), 222 property and subscript reads in the test
body (`app.buttons[...]`), 201 more reads inside `XCTAssert` autoclosures, 23 `XCUIApplication()`
initializers, and 22 writes to `launchArguments`. This is exactly
CCC's pattern, at about two-thirds of its size, spread over 14 files instead of 1.

**One build setting removes 662 of the 718.** T3 leaves 56 = 14 files × 4 override-isolation
warnings: `init()`, `init(invocation:)`, `init(selector:)`, and `setUpWithError()`, each now
main-actor-isolated while the `XCTestCase` declaration it overrides is `nonisolated`.

**The CCC `waitForExpectations` failure does not apply.** TTB's UI tests contain no
`waitForExpectations` and no `expectation(for:)` (0 matches on 2026-10-03).

**Unit tests differ from CCC.** CCC's unit suite was Swift Testing and was already clean. TTB's is
mostly XCTest and has 31 warnings in 8 files (section 3.6). Do not set main-actor-by-default on the
unit test target without measuring it first.

---

## 3. Diagnostic categories

Every one of the 202 stage-A3 warnings is in exactly one category below. A script assigned them, so
the per-category totals add up to 202. Counts measured 2026-10-03.

| Cat. | What the compiler flags | A3 warnings | Files | Needs design work? |
| --- | --- | --- | --- | --- |
| **B** | A `@MainActor` model passes its non-`Sendable` service existential into a `nonisolated` async call | **73** | 16 | No — mechanical |
| **D** | A service actor sends a Firebase SDK object out of its isolation | **33** | 10 | Yes |
| **C** | Listener-callback protocols: non-`Sendable` completion closures and handles cross an actor | **25** | 8 | Yes |
| **A** | `deinit` of a `@MainActor` class reads a non-`Sendable` listener handle | **20** | 11 | Small |
| **G** | UIKit callbacks and `DispatchQueue`/`Timer` closures not on the main actor | **19** | 3 | No |
| **H** | Compiler hint: "add `@preconcurrency` to suppress …" | **15** | 11 | Not a fix — see below |
| **F** | Global and static shared state | **9** | 9 | Small |
| **E** | `[String: Any]` Firestore/Functions payloads | **3** | 2 | Yes (shared with D) |
| **I** | Not concurrency (unused `Task` result, `weak` capture) | **3** | 2 | No |
| **J** | `UNUserNotificationCenterDelegate` callback values | **2** | 1 | No |
| | **Total** | **202** | **40** | |

Two compiler limits appeared, and both must be in the record:

- `Models/QuestionModel.swift:121`: "pattern that the region-based isolation checker does not
  understand how to check. Please file a bug". It is a warning in A3 and appears at 5 sites in A4.
  The message says it is an error in the Swift 6 language mode, so the call must be restructured
  before stage 6. It is counted in category C.
- `failed to produce diagnostic for expression` (the CCC large-`body` defect): **not seen** in any of
  the 13 builds.

### 3.1 Category-by-category, with the fix that holds up

No fix below uses `@unchecked Sendable` or `nonisolated(unsafe)`. Each fix is a candidate until a
re-measure after it shows the count fall.

**B — service existentials crossing from `@MainActor` (73).** Example: `SharedQuestionListStore`
(`@MainActor`) calls `try await service.revokeShare(...)`; `service` is
`any QuestionListShareServicing`, which is not `Sendable`, and the requirement is `nonisolated
async`, so the call sends `self.service` off the main actor. The 30 `sending 'self.service'`
warnings, plus `self.store`, `self.dependencies.auth`, `self.aiService` and similar, are all this
one shape. Fix: make the service protocols `Sendable` (`QuestionListShareServicing`,
`QuestionListServicing`, `FavoriteServicing`, `QuestionModerating`, `CategoryReading`,
`ContentReleaseReading`, `BadgeStoring`, and the `AuthModelDependencies` services). The live
conformers are already `actor`s, which are `Sendable`; the in-memory conformers are `@MainActor`,
which are `Sendable` too. Test doubles that are plain classes must become `actor`s or `@MainActor`.
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` also removes all 73 (stage A3m), but it adds 69 elsewhere
(section 3.4). `NonisolatedNonsendingByDefault` alone cannot be judged yet: it failed the build
(stage A3n), and at partial coverage 3 category-B warnings remained. Both are language-semantics
changes, so they are a separate decision (stage 5).

**D — Firebase SDK objects leaving a service actor (33).** The 19
`sending 'self.functions.httpsCallable'` warnings are the largest group: an `actor` stores
`Functions`, builds an `HTTPSCallable` from it (actor-isolated region), and awaits its
`nonisolated` `call(_:)`. The same shape: `StorageReference` in `ImageService` (4 `ref`, 1
`StorageMetadata`), `Firestore` in `QuestionService.runTransaction` (1), auth users (`AuthModel.swift:351` and
`AuthModelDependencies.swift:235` send TTB's non-`Sendable` `any AuthModelUser` wrapper;
`AuthModelDependencies.swift:28` sends Firebase's `authResult` through a continuation), and the 5
baseline warnings in
`AccountDeletionOperations.swift` (retroactive `Sendable` on `User`; a `Sendable` struct that stores
`Firestore`, `Functions`, `LocalFileManager`). Firebase 11.7.0 does not mark these types `Sendable`:
`HTTPSCallable` and `HTTPSCallableResult` are `open class … NSObject`, and the typed
`Callable<Request, Response>` struct does not declare `Sendable` either, so moving to the typed API
alone does not clear this. Candidates, to verify one service at a time:
1. Do not keep `Functions`/`Storage` objects as actor state. Get them in the method
   (`Functions.functions(region:).httpsCallable(name)`), so the value starts in a disconnected region
   and can be sent. Unverified — measure it on one service first.
2. Replace the retroactive `extension User: AccountDeletionAuthUser` with a `Sendable` value snapshot
   (`uid`, `isAnonymous`, `email`), and keep the live `User` inside one isolation domain. Make
   `LiveAccountDeletionOperations` an `actor` instead of a `Sendable` struct.
3. Upgrade `firebase-ios-sdk` if a later version annotates these types. Check its release notes; the
   upgrade is its own ticket.

**C — listener-callback protocols (25).** `favoritesListener(userId:onChange:)`,
`ownedSharesListener`, `acceptedRecipientsListener`, `setupQuestionListsListener` and the four
`QuestionModel` listener setups take a non-`@Sendable` `(Result<…>) -> Void` closure and return a
non-`Sendable` handle (`any ListenerRegistration` or a TTB handle protocol) across an actor boundary.
Fix: mark the callbacks `@Sendable` (or `@MainActor` where the only consumer is a main-actor model),
and make TTB's own handle protocols (`FavoriteListenerHandle`, `QuestionListShareListenerHandle`,
`BadgeUserListening`) `Sendable`, backed by a type that owns the registration. Firebase's
`ListenerRegistration` is not `Sendable`, so a TTB handle must wrap it. The longer-term shape is an
`AsyncStream` per listener; that is a larger change and not needed to reach Swift 6.

**A — `deinit` cleanup of listener handles (20).** Every `@MainActor` `ObservableObject` that owns a
Firestore or Auth listener removes it in `deinit`, and `deinit` is `nonisolated`, so reading a
stored non-`Sendable` property there is flagged. Most are `ListenerRegistration?` or
`AuthStateDidChangeListenerHandle?`; the others are TTB handle protocols
(`(any FavoriteListenerHandle)?`, `(any QuestionListShareListenerHandle)?`,
`(any BadgeUserListening)?`) and, in `AuthModel.swift:99`, the `dependencies` value that owns the
remove call. `QuestionModel` alone has 5. Two candidates:
1. `isolated deinit`. CCC probed it **available on iOS 18.4**. TTB targets **18.2**. Verify the
   floor before you use it; if it needs 18.4, it is a deployment-target decision, not a free fix.
2. Move the handles into a small `Sendable` owner whose state is a `Synchronization.Mutex`
   (`Mutex` is iOS 18.0, so it fits 18.2), and call its `removeAll()` from `deinit`. This needs no
   deployment-target change.

**G — UIKit and GCD callbacks (19 in 3 files).**
`Views/Main/SharedQuestionListViews.swift` (14): the `UIViewRepresentable` `Coordinator` is a plain
class, so its UIKit calls (`UIActivityViewController`, `present`, `popoverPresentationController`)
are not main-actor, and its `DispatchQueue.main.async` closure captures `self`. Fix: mark the
`Coordinator` `@MainActor`; the `DispatchQueue` hop is then a `Task { @MainActor in … }` or goes
away. `Views/Components/ImagePicker.swift` (3): the `NSItemProvider` completion calls a
main-actor method and captures `provider` in a `@Sendable` closure. `Views/AI/AILoadingView.swift`
(2): a repeating `Timer` closure mutates `@State`; replace it with a `.task` loop on
`Task.sleep(for:)`, which also stops the timer when the view goes away (today it never stops).

**H — "add `@preconcurrency`" hints (15).** The compiler offers `@preconcurrency import` for
`FirebaseFirestoreInternal` (8), `ObjectiveC` (6), and `FirebaseFunctions` (1). This downgrades the
module's `Sendable` errors to warnings; it fixes nothing. Do not take it as a category fix. The
hints go away when categories A–D are fixed. If one import is still needed for an un-annotated
Firebase module at stage 6, add it per file, with a comment that names the type that needs it.

**F — global and static state (9 in 9 files).** `KeychainManager.shared`, `LocalFileManager.shared`,
`AppLocalization.preferredLanguageCodesCache`, `AppEnvironment.none`, and the `EnvironmentKey`
`defaultValue`s in `AppEnvironmentModifier.swift`, `AppToast.swift` (`ToastCenter`) and
`PagedCardView.swift`, plus the mutable `static var dismissedQuestionIDs` in
`QuestionCardExpandedView.swift` and the main-actor default argument in
`UITestGuestFavoriteSeed.swift:15`. Fix each by making the type `Sendable` (a `final class` with only
`let`s, or a `Mutex`-guarded cache), by making the static `let`, or by `@MainActor` on the type where
only the UI uses it. For the `EnvironmentKey`s, the `@Entry` macro is the modern form.

**E — `[String: Any]` payloads (3).** See section 3.3.

**I — not concurrency (3), J — notification delegate (2).** I: `App/WindowTopmostPresenter.swift:55`
and `:57` discard a `Task`; `BadgeModel.swift:358` has a `[weak self]` capture that the outer scope
already captures strongly. J: `NotificationService.swift:244-245` send the delegate's `response` and
`completionHandler` into a `Task { @MainActor in }`. Fix J by doing the work in the `nonisolated`
delegate method, or with the `async` delegate variant.

### 3.2 The 22 `ObservableObject` types and the 5 `DispatchQueue` files — what Swift 6 actually flags

Inventory, 2026-10-03: 22 files declare one `ObservableObject` class each; 21 of the 22 are
`@MainActor`. The exception is `ToastCenter` (`Views/Components/AppToast.swift:78`); its `show(_:)`
is `@MainActor`, but the class is not.

**Swift 6 flags nothing about `ObservableObject` itself.** 0 of the 202 A3 warnings, and 0 of the
202 A4 warnings, name `ObservableObject`, `@Published`, or `objectWillChange`. A `@MainActor` class
that conforms to `ObservableObject` is clean under strict concurrency. Moving to `@Observable` is a
style decision (`swift-style-guide`), not a Swift 6 requirement, and it is out of scope for this
migration.

What the compiler does flag in those files: **120 warnings in 17 of the 22 files**, all from what
the models call or own:

| Category | Warnings in the 22 files |
| --- | --- |
| B — service existential crosses `@MainActor` | 67 |
| A — `deinit` reads a listener handle | 20 |
| H — `@preconcurrency` hint | 12 |
| C — listener callbacks | 13 |
| D — Firebase object | 1 |
| F — static state | 2 |
| J — notification delegate | 2 |
| E — `[String: Any]` payload | 2 |
| I — not concurrency | 1 |

The 5 files with **zero** warnings: `AnswerModel`, `GuestFavoriteModel`, `OnboardingViewModel`,
`AppDeepLinkRouter`, `MostAnsweredView` (`MostAnsweredViewModel`). The 3 heaviest:
`SharedQuestionListStore` (21), `QuestionModel` (16), `AuthModel` (15).

`ToastCenter` without `@MainActor` costs **1** warning: its `EnvironmentKey.defaultValue` is a
static of a non-`Sendable` type (`AppToast.swift:185`). Marking the class `@MainActor` makes it
`Sendable`; the static default value then needs a main-actor context, so fix it together with the
other `EnvironmentKey`s in category F.

**`DispatchQueue`: 8 call sites in 5 files; 0 diagnostics name `DispatchQueue`.** What the compiler
flags is what the GCD closures touch, because `DispatchQueue.main.async` takes a `@Sendable`
closure:

| File | `DispatchQueue` sites | A3 warnings in file | What is flagged |
| --- | --- | --- | --- |
| `Views/Main/SharedQuestionListViews.swift` | 1 (`:311`) | 14 | Non-main-actor `Coordinator` calls UIKit; the GCD closure captures `self` (G) |
| `Views/Components/ImagePicker.swift` | 3 (`:55`, `:73`, `:84`) | 3 | `NSItemProvider` callback calls a main-actor method; `provider` captured (G) |
| `Views/Components/AppToast.swift` | 2 (`:339`, `:349`) | 1 | Only the `ToastCenter` environment default (F); the GCD calls are clean |
| `Views/Components/BadgeUnlockView.swift` | 1 (`:117`) | 0 | Nothing |
| `Views/Authentication/RegistrationView.swift` | 1 (`:112`) | 0 | Nothing |

Swift 6 does not require removing these 8 calls. Replace the 4 in the category-G files
(`SharedQuestionListViews.swift`, `ImagePicker.swift`) as part of the G fix; the other 4 are style work for `swift-style-guide`, not migration work.

### 3.3 Firestore and Cloud Functions payloads (`[String: Any]` crossing isolation)

Inventory, 2026-10-03: 105 `[String: Any]` occurrences in 26 app files; 25 `httpsCallable` call
sites.

**Measured: only 3 payload warnings in A3** (5 in A4), because region-based isolation lets a
dictionary built in a local scope be sent once. A payload is flagged only when it comes from
isolated state:

- `Models/BadgeModel.swift:68` — `initialData` comes from the main-actor method
  `defaultBadgeUserFields()`, so it is in the main-actor region when it goes to `store.setUserDocument`.
- `Models/BadgeModel.swift:79` — `patch` merges values read from a document the store returned.
- `Services/AIService.swift:337` — `payload` is a parameter of an actor method, so it is in the
  actor's region when it goes to `HTTPSCallable.call(_:)`.

In A4 (main-actor default), `question.toFirestore()` and `stats.toFirestore()` also appear, because
the model encoders become main-actor.

**This count is low, but it is not the final count.** 19 of the 25 callable sites already warn about
the `HTTPSCallable` receiver (category D). Re-measure this category after D is fixed, because the
payload at the same call can report once the receiver no longer does.

Fix direction: keep the encoders pure and `nonisolated` (`defaultBadgeUserFields()`,
`toFirestore()`), so each call builds a fresh dictionary in a disconnected region, and pass
`sending [String: Any]` where a payload must go through an actor method. The deeper fix — `Codable`
`Sendable` request and response structs with Firebase's typed `Callable` and Firestore's
`Codable` support — removes `[String: Any]` from the boundary. It is larger than this migration
needs, and the typed `Callable` is itself not `Sendable` in 11.7.0 (category D). Treat it as a
separate decision.

### 3.4 What main-actor-by-default does here (A4 against A3)

A4 has the same total as A3 (202) in fewer files (32 against 40). A3m (main-actor default without
the nonsending flag) is identical to A4, so every change below comes from the isolation default. It
removes **all 73** category-B warnings, **all 9** category-F warnings, and most of G, and adds
**93 new warnings** that move the cost into the service actors:

- **69 in 18 files**: pure helpers and model factories that become main-actor, called from the
  service `actor`s — the `fromFirestore(_:id:)` factories, `progress(currentCount:targetCount:)`,
  `DownsampledImageDecoder.image(from:maxPixelSize:)`, `merge(localCandidates:…)`, `init(registration:)`
  on the listener handles, and the auth-user properties read in `AccountDeletionService`. This group
  includes 2 `expression is 'async' but is not marked with 'await'` (`ProfileModel.swift:295`,
  `QuestionService.swift:104`).
- **24 in 7 files**: main-actor static values read from the service actors — `prefersEnglish` (14),
  `currentLocale` (4), `legalVersion`/`onboardingVersion` (3), `aiPromptLanguageName` (1), and 2
  default values. The F count reads 9 → 24, but none of the 24 is one of the original 9.

This is CCC's issues #58–#66 shape: CCC cleared it by marking the callees `nonisolated` (value
types and pure helpers), not by adding hops at the callers. In TTB the service layer is `actor`s that
decode Firestore data, so a main-actor default puts that decoding on the wrong side of the boundary
at 93 sites. It is a separate decision, made on a re-measure (stage 5).

### 3.5 UI test target

All 718 T2 warnings are XCUI main-actor access from nonisolated XCTest methods (section 2). After
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on `TTBUITests` only, 56 remain, 4 per file, all
override-isolation: `init()`, `init(invocation:)`, `init(selector:)`, `setUpWithError()`. CCC fixed
the same class of warnings in its issue #67 (class `@MainActor`, `tearDownWithError()` →
`tearDown() async throws`). TTB has no `tearDown` overrides in the UI tests, and no
`waitForExpectations`. UI tests stay on XCTest.

### 3.6 Unit test target

31 warnings in 8 files under `complete` (T2), unchanged in T3:

- `GuestFavoriteModelTests.swift` (9): XCTest `setUp`/`tearDown` mutate main-actor properties of the
  test class from a nonisolated context.
- `InMemoryQuestionListShareServiceTests.swift` (6): the async `XCTAssertThrowsErrorAsync` helper
  takes non-`Sendable` closures.
- Category C in test doubles: `QuestionListShareTests.swift` (4 + 1 hint), `FakeFavoriteService.swift`
  (2 + 1 hint), `MockQuestionListService.swift` (2 + 1 hint). These go away with the app-side C fix.
- `AppEnvironmentServiceSlotTests.swift` (3): `sending 'store'` — category B on the test side.
- `MockAuthDependencies.swift:158` (1): `sending 'mockUser'`.
- `MockAccountDeletionOperations.swift:19` (1, also in the baseline): a `Sendable` class with a
  mutable `callLog`. Make it an `actor`, or guard `callLog` with a `Mutex`.

---

## 4. The language-mode and API facts this plan depends on

Three settings, three different limits — the CCC split holds here:

- `SWIFT_VERSION` sets the **language mode**. Moving to 6.0 changes strictness, not which iOS the app
  runs on.
- The **toolchain** is Swift 6.4. It accepts `SWIFT_DEFAULT_ACTOR_ISOLATION` and
  `NonisolatedNonsendingByDefault` at `SWIFT_VERSION = 5.0` (stages A3m, A4 build; A3n is accepted
  but fails on TTB code, section 2).
- `IPHONEOS_DEPLOYMENT_TARGET = 18.2` sets **API availability**. It is the real limit:
  `Synchronization.Mutex` (iOS 18.0) fits; `isolated deinit` was probed by CCC on 18.4 only and must be
  checked against 18.2; `Task.immediate`, `InlineArray` and `withTaskPriorityEscalationHandler` carry
  an iOS 26 floor (CCC probe) and stay out of the app target.

---

## 5. Recommended staged path

The same shape as CCC: unwired xcconfig → strict checking on the app target → fix by category →
flip `SWIFT_VERSION` → default MainActor isolation as a separate decision. Each stage is a stopping
point: the app builds and ships at the end of every one. All counts measured 2026-10-03.

### Stage 0 — commit the measured settings, unwired

Add `Config/StrictConcurrency.xcconfig`, in CCC's form: every setting commented out, each with its
measured count and date, and the hard rule at the top — never set `SWIFT_STRICT_CONCURRENCY` on the
`xcodebuild` command line or project-wide (CCC: it crashed the compiler on the `FirebaseAuth`
package target). Do not touch `project.pbxproj` in this commit. It conflicts with no branch.

### Stage 1 — UI test target (1 setting, 718 → 56)

Set `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on
`TTBUITests` only. Measured: `** TEST BUILD SUCCEEDED **`, 718 → 56. Then fix the 56
override-isolation warnings (4 per file, 14 files). Run the UI tests on iPhone 12 / iOS 26.5 to
confirm they still pass, because main-actor isolation changes where the test bodies run.

### Stage 2 — app target to warning mode

Set `SWIFT_STRICT_CONCURRENCY = complete` on the `TTB` target only, still at `SWIFT_VERSION = 5.0`.
Measured: 202 warnings in 40 files, 0 errors, full coverage, build succeeds. There is no blocker to
clear first (CCC had one; TTB has none). The project can ship with these warnings while stages 3–4
run alongside feature work.

### Stage 3 — unit test target to warning mode

Set `SWIFT_STRICT_CONCURRENCY = complete` on `TTBTests`. Measured: 31 warnings in 8 files. CCC
skipped its test targets at this point and paid for it at the flip (its issue #57: the first
`SWIFT_VERSION = 6.0` attempt failed on the UI tests). Do not skip it here.

### Stage 4 — fix by category, smallest risk first

Each line is one ticket, one small commit, and a re-measure that must show the count fall.

| # | Ticket | Count (2026-10-03) | Files |
| --- | --- | --- | --- |
| 4.1 | I + J: unused `Task`, `weak` capture, notification delegate | 5 | 3 |
| 4.2 | F: global and static state, `EnvironmentKey`s, `ToastCenter` | 9 | 9 |
| 4.3 | G: `@MainActor` `Coordinator`, `ImagePicker`, `AILoadingView` timer; their 4 `DispatchQueue` hops | 19 | 3 |
| 4.4 | B: `Sendable` service protocols, test doubles to `actor`/`@MainActor` | 73 (+3 unit) | 16 |
| 4.5 | A: listener handles in `deinit` (decide `Mutex` owner vs. `isolated deinit` on 18.2 first) | 20 | 11 |
| 4.6 | C: `@Sendable` listener callbacks, `Sendable` TTB handle types; restructure `QuestionModel:121` | 25 (+8 unit) | 8 |
| 4.7 | D: Firebase objects in service actors — prove the fix on one service, then the rest | 33 | 10 |
| 4.8 | E: payloads — re-measure after 4.7, then fix | 3 (re-measure) | 2 |
| 4.9 | Unit-test remainder: `GuestFavoriteModelTests`, `XCTAssertThrowsErrorAsync`, mocks | 17 | 4 |
| 4.10 | H: confirm the `@preconcurrency` hints are gone; keep any needed import with a reason | 15 | 11 |

4.4 is the biggest count and the least risk. 4.6 and 4.7 are the only tickets that need design
work; 4.7 may need a Firebase upgrade, which is its own ticket.

### Stage 5 — decide on default actor isolation and nonsending, on evidence

Two separate settings, two separate decisions, after stage 4:

- `NonisolatedNonsendingByDefault`: on its own it fails the build today, with 26 errors in
  `InMemoryQuestionListShareService.swift` (stage A3n). On top of the main-actor default it changes
  nothing (A3m = A4). It changes where every `nonisolated async` function in the module runs. Find
  the cause of the A3n errors first, then decide on a re-measure.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: today it moves cost from the models into the service
  actors (93 new sites, section 3.4) for a net change of 0 (202 → 202). CCC adopted it after its flip (PR #73)
  and cleared the cost with `nonisolated` on callees. Re-measure after stage 4 and choose then.

### Stage 6 — flip `SWIFT_VERSION` to 6.0

Last, and only when stages 2 and 3 report 0 warnings **and** 0 macro-expansion diagnostics. Set it on
all 6 configurations, then remove `SWIFT_STRICT_CONCURRENCY` (Swift 6 implies `complete`; CCC
issue #70, PR #72). Expected: uneventful. If it is not, a warning-mode stage was not finished.

### Why not the other order

Flipping `SWIFT_VERSION = 6.0` first is measurably worse. A5 reached 158 of 181 files and A5b 135,
and they disagree on which files they saw. T4 reached 18 of 49 unit files and 0 of 14 UI files. In
error mode you cannot see the size of the problem. Warning mode reported all 202 at full coverage
on the first run.

---

## 6. Risks

- **The FirebaseAuth compiler crash (CCC).** Not reproduced, because no setting here reached the
  package targets. Keep it that way: settings go on TTB's own targets only.
- **Category D depends on Firebase.** If no source change clears the `HTTPSCallable` and
  `StorageReference` sends, the options are a Firebase upgrade or a `@preconcurrency import` with
  a documented reason. Neither is `@unchecked Sendable`.
- **`isolated deinit` on iOS 18.2.** Unverified. The `Mutex` owner avoids the question.
- **Compiler limit at `QuestionModel.swift:121`.** The region checker cannot check that pattern; in
  Swift 6 mode it is an error. Restructure the call (4.6).
- **`NonisolatedNonsendingByDefault` breaks the build on its own** (26 errors, one DEBUG-only file,
  cause unknown). Never turn it on without the stage-5 investigation.
- **Toolchain drift.** Swift 6.4 / Xcode 27.0 (27A266a). Re-run Appendix A on a new toolchain
  before trusting these counts.
- **Uncommitted work.** These numbers are for `ca435bb`. The main checkout had an uncommitted edit to
  `Tests/HotPathBenchmarkTests.swift` on 2026-10-03 that this measurement does not include.

---

## Appendix A — measurement method

1. **Scope settings to a target, never the command line.** A Python patcher edits only the
   `XCBuildConfiguration` blocks whose `PRODUCT_BUNDLE_IDENTIFIER` matches exactly
   (`app.berke.can.kizildemir.ttb`, `…ttbTests`, `…ttbUITests`), and inserts the stage's settings
   beside that block's `SWIFT_VERSION`. A saved copy of `project.pbxproj` is restored after every
   stage, and `cmp` confirms it. After the last stage, `git status --short` was empty.
2. **Force a full recompile of TTB's targets only.** `rm -rf
   <dd>/Build/Intermediates.noindex/TTB.build` before each stage, with no `clean`, so the Firebase and
   Nuke builds survive.
3. **Build compile-only, with no simulator.**
   `xcodebuild -project TTB.xcodeproj -scheme TTB -configuration Debug
   -destination 'generic/platform=iOS Simulator' -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO build`
   (app stages) or `build-for-testing` (test stages). No simulator was booted. The generic destination
   builds `arm64` and `x86_64`; de-duplication removes the second copy of each diagnostic.
4. **Count honestly.** Extract `^<repo>/….swift:LINE:COL: (error|warning): msg`, de-duplicate on
   `(file, line, col, message)`, group by target folder, by file, and by message shape. Count
   separately: diagnostics outside the repository (0 in every stage), `macro expansion …` diagnostics
   (0 in every stage), and `failed to produce diagnostic` (0 in every stage). Coverage is the number
   of distinct target `.swift` paths that appear in a `SwiftCompile` command.
5. **Categorize by script.** Each diagnostic gets exactly one category from its message and file,
   so the category totals add up to the stage total.

Stage logs and scripts stayed in the session's scratch directory. They are machine- and
toolchain-specific and are not committed.

---

## Appendix B — CCC lessons, and whether they held here

| CCC lesson | TTB, 2026-10-03 |
| --- | --- |
| `complete` project-wide crashes the compiler on `FirebaseAuth` | Not tested on purpose; all settings target-scoped; no crash |
| Count in Swift 5 mode with `complete`; Swift 6 mode under-counts | Held: 181/181 against 158 and 135 |
| `-continue-building-after-errors` does not help error mode | Held: 158 → 135 |
| Count macro-expansion diagnostics separately | Done: 0 in all 13 builds (TTB has no SwiftData `#Predicate`) |
| Large `body` → `failed to produce diagnostic for expression` | Not seen; a different checker limit appeared (`QuestionModel.swift:121`) |
| UI tests: XCUI main-actor, XCTest nonisolated | Held: 718 warnings, 1 setting → 56 |
| `waitForExpectations` errors | Not applicable: no uses |
| Unit tests already clean | Did not hold: 31 warnings, XCTest-based suite |
| Main-actor default cuts the count | Did not hold: 202 → 202, cost moves into service actors |
| Measure the test targets before the flip (issue #57) | Built into stages 1 and 3 |
| Remove `SWIFT_STRICT_CONCURRENCY` after the flip (issue #70) | Built into stage 6 |
