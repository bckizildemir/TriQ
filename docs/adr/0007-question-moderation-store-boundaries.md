# The moderation store owns a second corpus, on purpose

`QuestionModerationStore` holds a `[Question]` that overlaps heavily with `QuestionModel.questions`.
Four of its boundaries read as inconsistencies and a review comparing it to `FavoriteStore` or
`AnswerDraftStore` will propose collapsing each. Each is a constraint.

## Two corpora, not one filtered corpus

The obvious objection is that one collection with a filter would be simpler than two collections that
can disagree. It would not, because they are not the same collection sampled differently.

`QuestionModel.questions` is the union of two Firestore listener queries: seeded questions, and
user-created questions that are *approved and placed on home*. The filtering happens in the query, so
the client never holds unapproved content and never has to remember not to show it.
`QuestionModerationStore.questions` is `getDocuments()` over the whole collection — pending and
rejected included — because that is the corpus a moderation queue exists to work through.

Sharing one collection means holding the admin superset and filtering on read. That is exactly what the
code did before this split, and it is the bug: `refreshAdminQuestions` wrote `getAllQuestions()` into
`questions`, `updateGroupedQuestions()` recomputed `groupedQuestions` from it, and
`CategoryQuestionsView` renders `questions(for:)` with no moderation filter of its own. So opening the
admin screen carried pending and rejected questions onto the category screens for the rest of the
session, since only a listener snapshot rebuilds the read model and that needs a write to a matching
document.

The two can disagree, and that is acceptable here in a way it would not be for the daily AI allowance
(ADR 0006). Nothing derives from their agreement: the admin screen reads only the moderation corpus,
every user screen reads only the read model, and a moderation write reaches the read model through the
listener that owns it. Compare this to the read model *containing* rows no screen should show, which is
a disagreement with a user-visible consequence.

Revisit if a second screen ever needs the unfiltered corpus. One reader is what keeps this cheap.

## Backend-first, with no optimistic path

`FavoriteStore` writes optimistically and rolls back, because a favorite tap must feel instant.
`QuestionModerationStore` awaits the write and patches afterwards, so a refused write cannot leave an
admin looking at a decision the backend rejected.

The asymmetry is in the act. Approving a question is a deliberate decision on one row behind a
confirmation-shaped UI, taken by one of a handful of people. There is no latency budget to defend and
no reason to accept the failure mode that optimism buys. Do not "make this consistent with
`FavoriteStore`" — the consistency would be cosmetic and it would add a rollback path with nothing
asking for it.

## The moderation rules are written twice, and agree by test

`Question.moderated(as:at:by:rejectionReason:)` trims the rejection reason, drops it for any status
other than `.rejected`, and clears `featuredPlacement` for anything that is not `.approved`.
`QuestionService.updateQuestionModeration` applies the same three rules when it builds its Firestore
payload. Two implementations of one rule set is normally the thing to fix.

It cannot be shared as written. The backend payload needs `FieldValue.delete()` to remove a field and
`FieldValue.serverTimestamp()` for the moderation time — neither of which a `Question` value can carry —
and the local copy needs concrete values because it is what the list renders until the next snapshot.
A single source would mean a third representation that both derive from, which is more machinery than
three rules justify.

So they agree by test instead. `QuestionModerationOperationsTests` asserts the local side against what
the service writes, and the assertions name the service method so the pairing is discoverable from
either end. Writing the fourth rule into only one side is the failure this arrangement is exposed to;
the tests are the guard, and a change to `updateQuestionModeration` must update them.

This pass already found one such divergence, latent: the service clears `featuredPlacement` for
`.pending` as well as `.rejected`, but the old caller passed `.none` only for a rejection. No screen
reaches `.pending`, so nothing had noticed.

## `AdminQuestionView` owns the store, so nothing can inject a fake into it

`FavoriteStore` is an `@EnvironmentObject` injected at the app root; `AnswerDraftStore` is an
`EnvironmentKey` with a lazy default (ADR 0005). This one is a `@StateObject` inside the screen.

The reason is lifetime. `ProfileView` builds `AdminQuestionView` inside a `navigationDestination`,
which SwiftUI re-evaluates on every parent update. A store passed in from there is a fresh instance on
each pass, discarding the corpus it just fetched. `@StateObject` is what survives that, and injecting
from the app root instead would put an admin-only module in every user's environment — a locality
regression, and the opposite of what AD-4 asked for.

The cost is that the *view* takes a live `QuestionService()` with no seam. That is deliberate and it is
why there is no null adapter here: nothing would call it. The store is tested directly through
`QuestionModerating`, which is where the choreography lives, and no UI test reaches the admin screen at
all — so a view-level seam would exist only to be unused, and an unused adapter in the app target is
how FIX-1 happened.

Revisit under AD-3, which is the entry that owns the question of where harness and preview wiring
belongs.

## Deliberately dropped: the answer-cache cleanup on delete

`removeLocalQuestion` cleared `currentUserAnswers[questionId]` when an admin deleted a question. The
store has no answer cache and does not reach into `QuestionModel`'s, so that no longer happens.

The stale entry is unreachable rather than merely harmless: every reader of `currentUserAnswers` keys
off a question that is being rendered, and a deleted question is not rendered. `mostAnsweredQuestions`
filters the read model for the same reason. The user-answers listener also replaces the whole map on
its next snapshot. Note that the delete itself never removed the `userAnswers` subcollection in
Firestore either — `deleteQuestion` deletes one document — so the backend keeps the answer regardless.
