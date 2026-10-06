# App Check proves the caller; the server owns the daily AI limit

FIX-4 was written as one problem: the callables accept requests with no app attestation. Reading the
code before designing turned up a second one that the survey had stated backwards, and the two
controls answer different questions. App Check answers *is this our app*. The daily quota answers
*how much may this account spend*. Neither substitutes for the other, so both landed together.

## The survey was wrong about the brake

FIX-4 said the per-user daily limit was the remaining brake, so abuse costs would scale with the
number of accounts an attacker was willing to create. There was no server-side brake at all.

`requireAuthenticated` in `aiProviderProxy.js` checked that the caller had a uid, and nothing else.
The 20-a-day limit lived in `AIUsageStats.dailyLimit` and `TrioPromptModel.hasReachedDailyLimit` — in
the client. The counter it checked itself against was `users/{uid}/aiUsage/stats`, which the client
also wrote, and `firestore.rules` validated the field types rather than the values. A caller could
write `dailyQueries: 0`; a caller invoking the callable directly never touched the document at all.
Anonymous sign-in makes a uid free. So the real figure was not "20 a day per account" but
"unbounded, from one account that costs nothing to create".

That is why this ADR exists for what the audit filed as config work.

## Enforcement goes on the six paid callables, not globally

`setGlobalOptions` would have covered all 30 functions with one line. The six AI callables already
shared `AI_FUNCTION_OPTIONS`, so scoping it cost nothing, and the other 24 have no money attached —
their blast radius is the caller's own data, which `firestore.rules` and their own ownership checks
already bound. Enforcement that fails takes a feature down, so it starts where the loss is asymmetric.

Revisit when the app has users and the App Check metrics show every client attesting: at that point
the argument flips, because a uniform rule is easier to reason about than a list.

## The quota is a second document, server-owned

`aiUsageDaily/{uid}` holds `{ dayKey, counts }` and is closed to every client — `allow read, write:
if false`, with the Admin SDK writing through it. The client's `users/{uid}/aiUsage/stats` document
was left exactly as it was.

One fact, two documents, is the thing to justify. The alternative was to make the server own the
existing document, which is the coherent design: one source of truth, the client reads and never
writes. It also means the server maintains `weeklyQueries`, `monthlyQueries`, `totalQueries`,
`lastQueryDate` and `favoriteCategory`, because screens display them, and it means reproducing the
client's calendar-based reset semantics on the server. That is a rewrite of the AI usage read model
inside a change whose point was to stop unbounded spend.

The cost of stopping here is a visible one: the client's counter and the server's counter can
disagree, so a caller can see "3/20" and still be refused. The refusal arrives as
`resource-exhausted`, which `AIService.mapFunctionsError` already maps to `.rateLimitExceeded`, so the
user gets a "too many requests" message rather than a wrong one. The client number is now display
only. The rule is recorded in `firestore.rules` next to both paths, because that file is where a
reader goes looking for who may write what, and the old document reads like a control.

Revisit when the AI usage screens are next touched — that is the moment the two numbers become one
person's problem, and the migration is cheap while nobody is looking at the history.

## Attempts count, not successes

Quota is spent before the handler runs. A provider error therefore costs the caller an attempt, and a
caller who retries into one does not get free calls: the money leaves when we call the provider, not
when the call succeeds.

The consequence is that a malformed request also costs an attempt, because the wrapper sits outside
the handler's own validation. Moving the check inside `aiProviderProxy.js` would fix that and would
make the brake optional at every call site — the handlers take their dependencies by injection, so a
forgotten argument would silently disable it, and the 93 existing tests would still pass. The wrapper
cannot be forgotten: `aiCallableWiring.test.js` fails if any AI export bypasses it.

## The provider choice is a value, not an `#if DEBUG` at the install site

App Attest does not work in the simulator, so debug builds need Firebase's debug provider, which
means harness-adjacent code in the app target. FIX-1 was exactly that shape, so the debug factory is
inside `#if DEBUG` from the first commit rather than merely unreachable in release.

`AppCheckPolicy.provider(for:)` maps an `AppCheckLaunchContext` to one of three choices and
`AppCheckInstaller` installs it. The split exists so the release case is asserted by a test running in
a debug build: `testAHarnessArgumentCannotWeakenAReleaseBuild` pins the guarantee that launch
arguments cannot downgrade attestation, which is not observable in the configuration the tests run in.

This is a seam of one decision, deliberately. AD-3 wants one seam for the whole harness layer; a
launch context and a policy function are small enough for AD-3 to absorb, and this change does not
pre-empt its interface.

FIX-4 expected the harnesses to need the debug provider and called that its one real decision. They
need the opposite. All 13 UI test files launch with a harness argument, every harness screen runs on
local fixtures, and `UITestAIRootView` injects `UITestTrioModelFactory`, so no UI test reaches an AI
callable. Harnesses therefore install nothing, and the UI suite gains no network traffic and no
console token to register. The debug provider is for ordinary simulator work.

## No monitoring period

Firebase's guidance is to monitor before enforcing, because enforcement rejects clients that do not
attest and old app versions take weeks to drain. There are no users, so there is nothing to drain and
the cost of waiting is the cost of leaving the callables open.

The order of operations moves instead of disappearing, and it is not reversible by deploying again:

1. Register the app for App Check with App Attest in the Firebase console.
2. Run the debug build once and register the debug token it logs.
3. Deploy the functions.

Deploying the functions first breaks the AI features for every build that is already installed,
including the one on the developer's own simulator. An App Check rejection arrives as
`unauthenticated`, which the client reports as a network error, so the symptom does not name its
cause.

## Not claimed

- The client-owned `users/{uid}/aiUsage/stats` document is still client-writable. It is no longer a
  control, so this is now cosmetic, but a reader who trusts it will still be misled.
- The `quickAnswers` limits (200 a day, 60 for a guest) are chosen to sit above a heavy session, not
  derived from measured use. Answer chips are requested once per question opened and fall back to
  local candidates when refused, so the failure is soft.
- `aps-environment` in `TTB.entitlements` was hard-coded to `development` and did not follow the
  configuration the way the new App Attest key does. Same shape of bug, different feature; untouched
  here, then **fixed separately as FIX-5** by applying this ADR's `APP_ATTEST_ENVIRONMENT` pattern to
  it. One thing FIX-5 found that applies to this ADR's key too: `aps-environment` is granted by the
  provisioning profile, so a Release build signed with a *development* identity may now fail to sign.
  Both keys were verified in the simulator only, which never checks a profile. See the FIX-5 entry in
  `Documentation/ARCHITECTURE_DEEPENING_AUDIT.md`.
- The other 24 callables remain unattested, `suggestAnswerImages` among them (superseded: ADR-0011 attests it with single-use tokens), which spends a
  third-party quota rather than money.
- One counter document per uid means concurrent calls contend on it. `QuestionCardExpandedView` asks
  for answer chips from a `.task(id:)` per card, so a fast scroll can overlap several. The Admin SDK
  retries a contended transaction, so the cost is latency rather than a lost count; nothing measures
  it yet. Sharding the counter is the answer if it ever shows up.
- The unit test target is hosted in the app, so the suite launches `AppDelegate` and installs the
  debug provider. Its token exchange fails until somebody registers a token, and the failure is a log
  line — `AppCheck failed` from Firestore, and `using placeholder token instead` from Auth. Detecting a
  test run in the app target would mean putting XCTest detection into the release binary, which is
  what FIX-1 removed, so the noise stays.

## Checking the release binary, for whoever does it next

`strings` on the release binary shows `AppCheckDebugProviderFactory` twice. That is the linked
`FirebaseAppCheck` framework, not app source — the same trap as the `XCTestConfigurationFilePath`
string already in there. The decisive check is the log line inside the `#if DEBUG` branch,
`App Check uses the debug provider`: absent from release, present in debug. Every
`-ui-test-…-harness` argument is absent from release too, `allHarnessArguments` included, because
nothing in a release build reads them and the optimizer drops the literals.

One catch: a debug build's app-target code is not in `TTB.app/TTB`, which is a 58 KB launcher. It is in
`TTB.app/TTB.debug.dylib`. Running `strings` on the launcher finds 106 strings and proves nothing.
