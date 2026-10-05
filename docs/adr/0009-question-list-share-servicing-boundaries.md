# The share-link service gets one seam, not a split

AD-5 extracts `QuestionListShareServicing` from the concrete `QuestionListShareService` actor, following
the pattern `ContentReleaseServicing` already set one directory over. Three of its boundaries are worth
recording, because the obvious move — copy the counterexample exactly — is not quite what this seam does.

## One protocol, not a reading/servicing split

`ContentReleaseServicing` splits into `ContentReleaseReading` (a narrow protocol) and the wider
`ContentReleaseServicing`, because two different consumers need two different surfaces — a detail view
model that only reads, and an admin flow that also writes.

`SharedQuestionListStore` is the only consumer of the share-link service, and it calls nearly every
method the actor exposes. Splitting the surface here would produce a "reading" protocol with no reader
and a second protocol carrying the rest — two names for one caller. `QuestionListShareServicing` is one
protocol, one-to-one with the methods the model actually calls. Revisit only if a second, narrower
consumer appears.

## The `UserDefaults` accepted-share cache is deleted, not migrated behind the seam

Before AD-5, `SharedQuestionListStore` kept two independent sources of truth for "am I a recipient of
this share": a `UserDefaults` cache of accepted share IDs, read at cold start to pre-populate
`acceptedShares` before the Firestore recipients listener answers the same question, and the listener
itself.

The cache is deleted rather than carried forward behind the new adapter. The cost is a cold start with no
pre-populated shares — but the view already renders a loading spinner, not an empty state, while
`isLoading` is true and the list is empty (`SharedQuestionListViews.swift:348`), and `isLoading` stays
true until the first listener snapshot resolves. So the visible cost is a slightly longer spinner, not a
wrong flash, and it buys one source of truth instead of two that can drift.

## `localOwnedShares:` stays, rebuilt on the in-memory adapter

Deleting the `guard let service else` fixture branches inside `SharedQuestionListStore` means `service`
becomes non-optional. The model's second initializer, `localOwnedShares:`, is not deleted along with
those branches — a reasonable reader might expect it to go, since it exists only to set `service` to
`nil`.

It stays because three production call sites (`AppEnvironment+UITest.swift`,
`UITestSharedQuestionListRootView.swift`) and roughly eight unit tests construct the model through it.
Rather than migrate every call site to build an in-memory adapter directly, `localOwnedShares:` is
rewritten to build that same in-memory adapter internally, seeded with the given shares, and delegate to
the one live-adapter code path. Callers and tests keep an unchanged signature; the model keeps exactly
one path through its code, not two.
