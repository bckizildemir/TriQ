# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Last updated

2026-11-11

Last session:
- Merged #127 (keep the unit-test host off live Firebase, drop the dead unauthenticated branch); #112 closed.
- Merged #126 (stop the client patch of server-owned stats on old user documents); #116 closed.
- Held #125 (reload badges after a guest upgrade): the code is right, but its badge test only checks a constant list, not the `ProfileView` reload. Finding is in a PR comment.
- Removed merged, clean worktrees (verify-99, verify-triq, wt-112, wt-116, the #90 nav-bar worktree).

## Open PRs

| PR | What it does | Waits for |
| --- | --- | --- |
| #125 | Reload badges after a guest upgrade; share-store tests; main-actor hop in the account adapter (#121) | A test that runs the real upgrade reload, then CI and merge |
| #129 | Add this STATUS.md and its pointer in CLAUDE.md | The owner's merge (docs only, CI skips iOS) |
| #128 | Dependabot: bump re2js 2.8.6 → 2.9.1 in `functions/` | The owner's merge decision |
| #95 (draft) | Record the Private Cloud Compute research for AI | The owner; agents leave it alone |

## Next step

1. Fix the #125 badge test (see the PR comment), rebase on main, merge, then close #121 (follow-ups from PR #120).
2. Open an issue for the other client writes of server-owned stats that the rules refuse: `QuestionService.backfillBadgeProgressIfNeeded` (`setData(..., merge: true)`) and the `totalAnswered` write in `ProfileModel` (same kind of bug as #116).

## Waits for the owner

- #128 (re2js bump in `functions/`): merge or not.
- #95 (draft, Private Cloud Compute research): finish or close.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): labelled `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
- Old worktrees kept because they hold work that no merged PR has:
  - `impl/53-one-listener-handle` and `impl/54-favorites-listener-call-site`: pushed, never had a PR.
  - `feat/60-92-tab-and-trio-chrome`: 3 uncommitted UI-test file changes (its PR #107 merged).
  - `worktree-agent-afe07a39aa03cfd1e`: 1 unpushed wip commit (iOS 18 grey band diagnosis, fixed later in #90).
  Keep or delete each.
