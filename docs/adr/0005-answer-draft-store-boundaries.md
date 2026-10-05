# The answer-draft store orchestrates but owns no state

`AnswerDraftStore` looks like `FavoriteStore` and is deliberately not built like it. Three of its
boundaries read as inconsistencies with AD-1 and will be proposed for collapsing by any review that
compares the two modules. Each is a constraint.

## The cache stays on `QuestionModel`

`FavoriteStore` owns favorite state; `AnswerDraftStore` owns none. It reaches the cached answer through
a three-method port that `QuestionModel` satisfies.

The asymmetry is in what the two facts are. A favorite is a boolean per question, read through
accessors, and moving it moved three resolvers. The cached answer is the app's answer read model:
eleven read sites across six view files, a Firestore listener writing into it, and `@Published`
observation by every screen that renders an answer. Moving it would mean migrating the listener behind
another seam and resolving who publishes — either the screens observe the store instead of the model,
or the model republishes what the store owns, which is the two-sources-of-truth problem AD-1 warned
about.

None of that is needed for the thing AD-2 existed to fix. Rollback and compare-and-swap need *access*
to the cached answer, not ownership of it, and a port gives them that with a fake in the tests. So the
store owns the choreography — the optimistic write, the upload fan-out, the compare-and-swap, the
rollback — and the state stays where its readers already are.

Revisit when something else forces the answer cache to move: AD-4 cutting moderation out of the
question read model is the likely trigger, since it touches the same model.

**Update, 2026-08-01: AD-4 landed and was not the trigger.** It moved the admin CRUD cluster into
`QuestionModerationStore`, which owns its own corpus and never touches `currentUserAnswers` — so the
answer cache stayed exactly where this decision left it, and the eleven read sites did not move. The one
thing AD-4 changed here is smaller than the decision above: `removeLocalQuestion` used to clear the
cached answer for a deleted question and no longer does, which ADR 0007 records. Do not wait for another
candidate; nothing on the current board forces this cache to move.

## `AnswerPersisting` is one method, not a `QuestionServicing` protocol

`QuestionService` is 792 lines and roughly thirty methods. The collapsed save path calls exactly one of
them. A protocol over the whole service would make every `QuestionModel` path testable and would kill
the `service == nil` local mode the audit calls an anti-pattern — but it would also drag Firestore
listener-handle abstraction into a change about saving answers, and it is AD-sized work in its own
right.

The narrow port buys what AD-2 needed: the persistence branch became reachable in tests at all. Before
it, `questionService` was a concrete optional and every test ran the branch where saving silently did
nothing, so nine tests asserted cache behaviour and would have passed with persistence entirely broken.

A consequence of stopping there: `AnswerDraftStore.persister` is optional, reproducing the existing
local mode where saving updates the cache and nothing else. That optionality is the AD-5 anti-pattern,
kept deliberately rather than papered over with a null-object adapter — which, given file-system-
synchronized groups, is precisely how FIX-1 got test doubles into a release binary. It should go away
with AD-3 or AD-5, not before.

## Injected by `EnvironmentKey`, not `@EnvironmentObject`

`FavoriteStore` is an `@EnvironmentObject`, so AD-1 had to add it to six UI-test harness roots. Nothing
observes `AnswerDraftStore` — it publishes no state, by the first decision above — so it is an
`EnvironmentKey` with a default instead. A harness that forgets an environment object crashes at
runtime; a harness that never overrides an environment key gets the default and works.

The default is built lazily, so a harness that never saves an answer never constructs a Firebase
client.

It does **not** retire a launch-argument leak. An earlier revision of this ADR claimed it moved the
`shouldSkipFirebaseConfiguration` check out of a `View`'s initializer and into one adapter, retiring
one of the four AD-3 lists. That is false, and it is backwards: AD-2 **added two** sites rather than
retiring one.

- `TTB/Services/AnswerDraftPorts.swift:115` — `LiveAnswerImageStore`'s own copy of the check.
- `TTB/Models/AnswerDraftStore.swift:214` — the same check again, for the persister default.
- `TTB/Views/Components/QuestionCardExpandedView.swift:155-158` — still there, holding two: one for
  `AIService`, and one for the very same `AnswerImageSuggestionService` the adapter builds.

The check was copied, not moved. AD-3 now has six sites to gather rather than four; its file list
records them.

**Update, 2026-08-06: AD-3 gathered them, and the optionality stayed.** All three sites above are
gone. The construction decision sits on `AppEnvironment`, which supplies the persister and the
suggestion service, so `LiveAnswerImageStore` and `QuestionCardExpandedView` take what they were given
instead of asking a launch argument. `AnswerDraftStoreKey.defaultValue` is now cache-only rather than
live, which is this ADR's own direction: a screen that was never wired gets an inert store.

What did **not** change is `persister`'s optionality. AD-3 found that the three optionals are not one
pattern — `aiService == nil` and the image-suggestion nil branch are designed fallbacks with visible
behaviour, while this one is the plain local mode. Removing it needs a fake that saves for real, so
the "or AD-5" in the paragraph above is now the whole answer. `docs/adr/0008` records the reasoning.

Do not "make this consistent with `FavoriteStore`" by converting it to an environment object. The
consistency would be cosmetic and the cost is seven harness files plus a class of runtime crash that
the current shape cannot have. If anything, `FavoriteStore` is the one to revisit — but only once
something needs to observe it that does not already.
