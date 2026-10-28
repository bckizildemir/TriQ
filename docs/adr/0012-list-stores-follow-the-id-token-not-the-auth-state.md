# The list stores follow the ID token, not the Auth state

`QuestionListStore` and `SharedQuestionListStore` learn the signed-in permanent account through
`PermanentAccountObserving`. The live adapter registers `Auth.addIDTokenDidChangeListener`. It does not
register `addStateDidChangeListener`.

## Why

Issue #119: linking a guest to an email account keeps the same uid. Firebase fires the state listener
only when the uid changes, so the stores kept `userId == ""` and `createList` threw
`permanentAccountRequired` until the app relaunched. `AuthModel` calls `forceRefreshIDToken()` after the
link, and the ID-token listener fires on a link, a sign-in and a sign-out.

## Considered options

- **Reuse the `AuthModel` upgrade signal.** Rejected: the stores are built without an `AuthModel` and
  stay independent of it, and a second path would still need its own test seam.
- **Keep the state listener and re-read `currentUser` on demand.** Rejected: the lists listener must
  attach for the permanent uid, so the store needs an event, not a poll.

## Consequences

- The ID-token listener also fires on the hourly token refresh. `transitionToUser(withID:)` returns early
  when the uid is unchanged, so a refresh does not restart a listener or clear state.
- The Firebase call is one line in `LivePermanentAccountObserver`. The uid mapping is the pure function
  `permanentUserID(uid:isAnonymous:)`, which a unit test covers. Fakes cover the stores.
- Stores that key on the uid only (`ProfileModel`, `QuestionModel`, `NotificationService`) do not change
  on a link. `BadgeModel`, `AIModel` and `TrioPromptModel` read `currentUser` at call time.
  `FavoriteStore` takes its identity from `AuthModel`, which refreshes after a link.
