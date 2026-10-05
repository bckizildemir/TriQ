# Guest upgrade is presented per screen, not from the app root

> **Superseded in part by `0010-upgrade-prompt-presents-from-the-topmost-controller.md`.** The two
> root-owned sheets — the favorite-limit prompt and the guest-upgrade sheet it opens — now present from
> the topmost controller, so they appear over covers. The three per-screen flags below still stand
> until they move behind that host.

The guest-upgrade sheet and the favorite-limit sheet are presented by the screen that triggers them,
not by a single root-owned host, even though the root already observes the flags that drive them.
This looks like duplication and gets flagged as such by architecture reviews; it is a constraint.

`FavoritesContentView` is pushed inside `ProfileView`, which is itself reachable as a
`fullScreenCover` from Home, and `QuestionCardExpandedView` is presented as a cover in its own right.
A root-owned sheet asked to present from underneath an active cover does not appear. So the screens
that live inside covers keep local presentation state, and only the screens that sit directly under
the root use the root's flags.

We chose this over a root-owned presentation host because the host would have to know which covers
are active and defer presentation until they dismiss — real sequencing logic serving a sheet with two
buttons. The duplication is three `@State` flags and three `.sheet` modifiers, which is cheaper than
that machinery and fails visibly rather than silently when it is wrong.

Revisit this when a presentation host exists for other reasons — a notice or toast host would be the
natural owner, and at that point the flags should move behind it. Until then, a review that proposes
collapsing these three paths into one is proposing a regression: the sheet stops appearing on the
Favorites screen and inside the expanded card.
