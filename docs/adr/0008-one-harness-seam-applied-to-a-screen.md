# The harness seam is a modifier on a screen, not an injectable root

AD-3 asked for one seam for the UI-test harness and proposed it as an injectable initializer on
`AppEnvironmentRootView` — "move every harness onto the injectable init". Reading the code before
designing turned that around. The seam is `AppEnvironment` plus `appRoot(_:)`, and no harness renders
the app root at all. Five of these boundaries read as inconsistencies with the entry that asked for
them. Each is a constraint.

## Harnesses apply `appRoot(_:)` to their own screen

`AppEnvironmentRootView` renders `AppRootView`, which switches on auth state, and its `.authenticated`
branch renders `AuthenticatedRootView`. That view builds `OnboardingViewModel()` as a `@StateObject`
with no seam, and `OnboardingStateStore` constructs `Firestore.firestore()` and calls `getDocument()`.
The call throws in a harness, `loadState` sets `shouldShowOnboarding = true`, and the harness lands on
`OnboardingFlowView`. So a harness that renders the real root reaches the onboarding flow rather than
the screen its test drives.

The entry said one harness already proved the injectable init. It did not. `UITestSharedQuestionRootView`
built a plain `AuthModel`, which reports signed out without Firebase auth, so `AppRootView` showed
`LoginView` and the deep-link sheet presented over the login screen. Its one test asserts only on the
sheet, so nothing noticed. The authenticated root has never been exercised by a UI test.

Putting a seam on the onboarding gate was the alternative, and it is a module AD-3's file list never
named — plus an auth-fixture requirement for all seven harnesses and the full root chain on every
launch. Moving the *behaviour* instead costs nothing and delivers what the entry actually wanted: the
app root and every harness run the same favorite-limit sheet, guest-upgrade sheet, migration task,
deep-link routing and toast host, because there is one copy.

The consequence is that `AppEnvironmentRootView` has no injectable initializer and no test. That is
acceptable because its body is now two lines — `AppRootView().appRoot(environment)` — so there is
nothing left in it to diverge. What used to need injection is guaranteed by the modifier.

Revisit when something needs to test the onboarding gate or the auth switch. At that point the gate
needs its own seam, and that is the change to make, not this one.

## Foreground notification re-registration runs on shared code and still cannot be asserted

AD-3 listed four things reachable only on the production path and said the fix makes them testable.
Three of the four were right — and one of those three is still not assertable.

`NotificationService` is a 248-line singleton with a `private init`, a Firebase auth listener, a
Firestore device listener and `MessagingDelegate` conformance, so no harness can build a fixture.
`syncCurrentDeviceRegistration` returns at its first guard when `Auth.auth().currentUser` is nil and
again when there is no APNS token; harnesses use fixture auth and the simulator has neither. The path
therefore runs, on the same code as production, and does nothing observable.

Moving it behind `appRoot(_:)` is still worth doing: harness and production no longer have two copies
of it, which is the divergence AD-3 exists to remove. But AD-3 claims two assertable paths, not three.
The favorite-limit sheet and guest-favorite migration are covered by
`GuestFavoriteUpgradeFunnelUITests`; this one is not.

A `NotificationRegistering` interface would fix it and is AD-sized work overlapping AD-7. Revisit
there, not here.

## `AppCheckPolicy` keeps its launch-argument read

`docs/adr/0006` recorded `AppCheckPolicy.provider(for:)` as a seam of one decision and said AD-3 could
absorb it. It cannot. `AppCheckInstaller.install` runs in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`,
before any `View` exists, so a view modifier is the wrong lifecycle stage for it. Every other
launch-argument read in production code is gone; this one stays, and `testAHarnessArgumentCannotWeakenAReleaseBuild`
is what keeps it honest.

## A used fixture adapter under `#if DEBUG` is not the hazard ADR 0005 and 0007 named

Both of those ADRs refuse a null adapter in the app target, citing FIX-1 — `docs/adr/0007` says "an
unused adapter in the app target is how FIX-1 happened". AD-3's Direction asks for null adapters, which
reads as a contradiction.

The distinguishing word is *unused*. `AppEnvironment.uiTest` and `UITestFavoriteService` are called by
seven harnesses, sit in `TTB/UITestSupport/` under a top-level `#if DEBUG`, and follow the precedent
AD-1 set. What FIX-1 shipped was a type nothing called, guarded by nothing.

Discipline is not enough on its own, because `TTB/` is a file-system-synchronized root group with six
membership exceptions and no per-configuration membership, and there are only three targets — a
separate harness framework cannot see the app's `internal` types. So `#if DEBUG` is the only available
gate, and a tenth harness file still defaults to shipped unless something checks.

**Update, 2026-08-06: that check is written.** `6f24b42` gathered the nine harness roots and fixtures
from `TTB/App/` into `TTB/UITestSupport/`, and `Tests/HarnessLayerIsolationTests.swift` holds three
rules: no `UITest*` file lives outside that directory, every file in it opens with a top-level
`#if DEBUG` and closes with `#endif`, and only `TTBApp`, `AppCheckPolicy`, `UITestLaunchOptions` and
`HomeView` read the launch options at all. The third rule is the one that pins AD-3's purpose rather
than a naming convention — a new production reader fails the suite, and listing `HomeView` there is
what keeps FIX-6 visible. `UITestLaunchOptions` stays in `TTB/App/`, because `TTBApp` dispatches on it
and `AppCheckPolicy` consults it, so gating it would break the release build. The gate rule was
checked against an ungated file before it was trusted: it fails on both ends and names the file.

## `AppEnvironment` is an `ObservableObject` that publishes nothing

It has no `@Published` property and nothing observes it. It conforms anyway so it can be held by
`@StateObject`, whose `wrappedValue` is an autoclosure and therefore builds the live models once, on
first render. `@State` takes a plain value and would rebuild all eleven models on every `init` — each
one opening Firestore listeners.

One behaviour change comes with this. The old root held every model with `@StateObject`, so the
favorite-limit sheet's preview list re-rendered whenever `questionModel` changed. It is now read when
the sheet body is built and is a snapshot for as long as the sheet is open. That is acceptable — the
sheet shows the questions the guest already saved — and in a guest session the corpus is loaded long
before anyone saves ten favorites.

`AppRootBehaviourModifier` observes four of the models with `@ObservedObject`, where the old root held
all eleven with `@StateObject`. It needs exactly those four: three for sheet bindings and `authModel`
for the migration task id. The rest are read when a sheet body is built. Do not "make this consistent"
by observing the environment itself — that is the two-sources-of-truth problem AD-1 warned about, and
it would rebuild the whole behaviour block on every question snapshot.

## The harness auth fixture publishes a linked user

`AuthModel.linkAnonymousAccount` never updates `AuthModel`'s own state. It relies on the Firebase auth
state listener firing after the link, and `isAnonymous` is computed from `dependencies.auth.currentUser`.
`UITestAuthProvider` called its listener once at init and `UITestAuthUser.link` returned a new object
without telling the provider, so a fixture guest stayed anonymous after a successful upgrade. Nothing
noticed, because no test had ever driven an upgrade.

`link` now publishes through the provider's stored listener, which is what real Firebase does. The
other four mutators — `signIn`, `createUser`, `signInAnonymously`, `signOut` — still swap `currentUser`
without notifying, because that is what the thirteen existing UI tests were written against. Widening
it is a separate change with its own suite run.

## The service slots keep their optionality, and only the decision moves

AD-3's Direction asked for "interfaces with null adapters". Reading the three call sites says the
adapters would change what the user sees, so the change moves the *construction decision* onto
`AppEnvironment` and leaves the optionality where it is.

`aiService == nil` is a designed no-AI fallback rather than "do not construct". In
`loadQuickAnswerSuggestions` the nil branch and the `catch` branch reach the same state, so a fake
returning empty arrays is equivalent — but one that throws is not, and in `fillWithAI` a throwing fake
shows an AI error for three seconds where nil shows nothing. `AnswerImageSuggesting` would be two
methods, not the one the entry assumed, and its nil branch sits beside a `catch` for
`AnswerImageSuggestionServiceError.noResults`, so a fake would have to throw that exact error to
match. Only `AnswerDraftStore.persister` is the plain local-mode anti-pattern `docs/adr/0005` named.

So `live()` supplies the real three and `uiTest()` supplies none, which retires four launch-argument
reads with no behaviour change at all. Killing the optionality needs fakes that save and suggest for
real, and `docs/adr/0005` already named AD-5 as the alternative owner. Revisit there.

The keys default to `nil` and to a cache-only store, so a screen rendered outside `appEnvironment(_:)`
gets an inert service rather than a live one. That direction has a cost worth stating: production
save now depends on SwiftUI carrying environment values into a presented sheet or full-screen cover,
and the editor reaches users through eleven `QuestionDetailModalShell` presentations plus one
navigation destination, none of which re-applies the modifier. No UI test can discriminate this,
because inside a harness the injected store and the default store are both cache-only. It was checked
by hand instead: answer a question, stop the app, start it again, and the answer comes back from
Firestore. Repeat that check if a screen ever renders the editor from a new context.

## The sheet dismiss delay is a value, not a flag

`SimulatorSafeSheetDismissButton` refuses its own tap for 700 ms so a UI test cannot dismiss a sheet
before the simulator finishes presenting it, and it read `isHomeProfileQuestionListHarnessEnabled` to
decide. Eight production sheets use the button, so the type stays; what goes is its knowledge that a
harness exists. The delay is a `Duration` on `AppEnvironment`, installed through an `EnvironmentKey`
defaulting to zero, and `UITestHomeRootView` states 700 ms when that harness launched it.

This is the one field on `AppEnvironment` that is not app wiring, and a review called that out as a
type changing for two reasons. It is accepted deliberately: the alternative leaves a production view
naming one harness, which is the thing AD-3 exists to remove.

## Not claimed

**Update, 2026-08-06: the first entry on this list has since landed.** The service slots moved onto
`AppEnvironment` in `efb2748`, the sheet dismiss delay in `7af653f`, and the `#if DEBUG` gate in
`6f24b42`. The two decisions those raised are recorded at the end of this file. The rest of this list
still stands.

- **`BadgeModel` is untouched, and its guard covers one construction site of four.** `HomeView`
  consults a launch argument before building one; `ProfileView`, `AnswersContentView` and
  `MostAnsweredView`'s no-argument init build one with no guard at all, so harnesses open a live badge
  listener today and still do. Recorded as its own FIX in
  `Documentation/ARCHITECTURE_DEEPENING_AUDIT.md` rather than folded in here — it needs a port over a
  six-operation Firestore surface and an answer for two `@StateObject` observation sites.
- **`shouldSkipFirebaseConfiguration` is still misnamed.** Both branches of
  `AppDelegate.application(_:didFinishLaunchingWithOptions:)` call `FirebaseApp.configure()`; the flag
  only skips `NotificationService.shared.configure(application:)` and the launch remote notification.
  What the service-construction guards actually prevented was network traffic, not an unconfigured
  Firebase. The remaining reader is `AppCheckPolicy`, so renaming it is cheap and was left out to keep
  this change reviewable.
- **The deletion is not the ~700 lines the entry predicted.** The harness roots and the old root lose
  roughly 320 lines, and the shared seam adds roughly 330, so the line count is close to flat. The
  entry counted the duplication without counting what replaces it. What actually changed is that eight
  wirings became one, and two paths that no test could reach now have tests.
