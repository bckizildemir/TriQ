# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Last updated

2026-11-11

Last session:
- With the owner's yes, merged #137 (STATUS.md record of the earlier session), #135 (Hosting targets `main`
  and `triq`), #132 (fast-xml-parser bump in `Scripts/seed_questions/`), #131 (fast-xml-parser 5.7.3 → 5.12.0
  in `functions/`) and #95 (Private Cloud Compute research, now in `Documentation/`).
- Functions deploy for #131, with the owner's yes: all 32 functions in groups of 3, 20 s apart. Three hit
  "Quota exceeded for total allowable CPU" (`suggestAnswerImages`, `generateTrioQuestionSuggestions`,
  `resolveUsername`); a retry of only those names fixed them. The CLI did not name `resolveUsername` as failed:
  check `gcloud run services list` for `latestReadyRevisionName` = `latestCreatedRevisionName` on every service.
  All 32 matched at the end. verify-triq after the deploy passed guest onboarding + Home, the guest upgrade
  (`claimUsername`) and the signed-in Home (`~/verify-evidence/triq/2026-11-11-201545-30c6`). Not checked: a
  server Cloud Storage path (no feature file for suggested answer images), where fast-xml-parser is used. #128 (re2js bump) and #133 (1 instance
  per function) were already live on all 32 functions before it (every function updated 2026-11-11 00:12-00:47 UTC,
  max instances 1).
- New rule "Safe merges" in CLAUDE.md: agents merge green docs-only PRs and Dependabot patch/minor bumps
  themselves; a functions bump still needs the owner's yes for its deploy, asked in the same message.

## Open PRs

None.

## Next step

1. Triage #136 (Profile closes and Home shows after a guest upgrade): decide if the jump to Home is wanted.
2. Open an issue for the other client writes of server-owned stats that the rules refuse: `QuestionService.backfillBadgeProgressIfNeeded` (`setData(..., merge: true)`) and the `totalAnswered` write in `ProfileModel` (same kind of bug as #116).
3. Remove the merged worktrees `../wt-t-hosting` (#135) and `../wt-t-skills` (#140) once nothing local is left in them.

## Waits for the owner

- #139 (before release, check that 1 instance per function is enough for launch traffic): `ready-for-human`.
- #138 (a verification loop after deploys and merges): `ready-for-human`.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): labelled `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
