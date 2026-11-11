# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Last updated

2026-11-11

Last session:
- Merged #127 (keep the unit-test host off live Firebase), #126 (stop the client patch of server-owned stats), #128 (re2js bump, fixes the high Dependabot alert), #129 (this file) and #125 (reload badges after a guest upgrade). Issues #112, #116 and #121 closed.
- #125 got a real test first: the guest-upgrade reload plan now runs through `ProfileAccountRefresh.run`, and the test goes red without the badge reload.
- The simulator check of #125 found that the app closes Profile and shows Home after a guest upgrade; opened as #136. Two live test accounts were made for it (listed in the verify-triq accounts memory).
- Deleted all old and merged worktrees; only draft #95's worktree is left.

## Open PRs

| PR | What it does | Waits for |
| --- | --- | --- |
| #135 | Add the Hosting targets `main` and `triq` to the Firebase config (owner's PR) | The owner; CI green |
| #131 | Dependabot: bump fast-xml-parser 5.7.3 → 5.12.0 in `functions/` | The owner's merge decision; CI green |
| #132 | Dependabot: bump fast-xml-parser 5.11.2 → 5.12.0 in `Scripts/seed_questions/` | The owner's merge decision; CI green |
| #95 (draft) | Record the Private Cloud Compute research for AI | The owner; agents leave it alone |

## Next step

1. Triage #136 (Profile closes and Home shows after a guest upgrade): decide if the jump to Home is wanted.
2. Open an issue for the other client writes of server-owned stats that the rules refuse: `QuestionService.backfillBadgeProgressIfNeeded` (`setData(..., merge: true)`) and the `totalAnswered` write in `ProfileModel` (same kind of bug as #116).

## Waits for the owner

- A functions deploy so the re2js fix from #128 (and #131 if merged) runs on the server. A deploy needs the owner's yes.
- #131, #132 (fast-xml-parser bumps) and #135 (Hosting targets): merge or not.
- #95 (draft, Private Cloud Compute research): finish or close.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): labelled `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
