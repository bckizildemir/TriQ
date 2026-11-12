# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Last updated

2026-11-12

Last session:
- Owner decisions: the jump to Home after a guest upgrade is intended (#136, closed; recorded in
  verify-triq `features/profile.md`). `CONTEXT.md` renamed to `GLOSSARY.md` (#143).
- Merged: #149 (verify-triq check loop after deploys and merges + `features/changes.md`, closes #138),
  #150 (user-flow statecharts in `Documentation/flows/`), #148 (an "AI can make mistakes" notice on every
  AI result, closes #144; proved on the simulator, run `2026-11-12-013055-7ec4`), and three formal checks:
  #145 (guest upgrade identity), #146 (question list sharing), #147 (AI quota pools).
- The formal checks found bugs, now issues: #151 (guest upgrade: a username can get stuck, shown twice or
  lost), #152 (an old share link still admits after Regenerate; a reply lands after Remove or Revoke),
  #153 (the per-user AI daily limit can be beaten at midnight or by deleting the account).
- Owner rules: AI calls are allowed while the models are free (live check 2026-11-12: `AI_PROVIDER=groq`);
  axe is the only simulator driver. Image suggestions are a Pexels photo search, not AI: no AI notice
  (pending the owner's final word).
- verify-triq maintenance pass NOT run: `/maintain-verification-skill` can only be started by the owner.
  The worktree `../wt-t-maint` (branch `verify/maintenance-2026-11-12`) waits for it.

## Open PRs

None.

## Next step

1. Fix #151, #152 and #153 (the formal-check bugs).
2. Owner runs `/maintain-verification-skill` for verify-triq (drift notes: profile ids, question card
   wand/menu/Find Image, home feed list button, guest favorites toast, sign-in form, Trio composer, a new
   `question-lists.md`).
3. Open an issue for the other client writes of server-owned stats that the rules refuse:
   `QuestionService.backfillBadgeProgressIfNeeded` and the `totalAnswered` write in `ProfileModel` (same kind of bug as #116).

## Waits for the owner

- #139 (before release, check that 1 copy per function is enough for launch traffic): `ready-for-human`.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
