# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Focus

Fix the three bugs the formal checks found (owner, 2026-11-12): done, 3/3. Next focus not chosen yet.
- #151 (guest upgrade username): fixed in #161
- #152 (old share link; late reply): fixed in #159
- #153 (AI daily limit at midnight / after delete): fixed in #160

## Last updated

2026-11-13

Last session:
- 2026-11-13 (verification upkeep): all three formal checks (guest upgrade identity, question list sharing, AI
  quota pools) pass on `origin/main` after the fixes #159, #160, #161; no new bug. #169 (formal: sync commits and
  line references after the fixes) moves the models' bookkeeping forward; it waits for the owner because it holds a
  `.tla` file. `CLAUDE.md` has a new section "Re-check everything": the one command for all formal checks and the
  verify-triq check loop step. #168 opened (client writes of server-owned answer stats are refused by the rules:
  badge backfill, `totalAnswered` migration). #167 (STATUS.md, build 11 went to the external testers) merged.
- 2026-11-13: #163 merged: the app shows as "TriQ" on the Home Screen (display name, photo permission text,
  3 strings), build number 11. App Store Connect name is now "TriQ: Answers in Threes". Left as "TTB": the
  `"TTB user"` fallback name in 5 Swift files and the list-share web page text in `functions/` (needs a deploy).
  TestFlight: build 11 is uploaded, `VALID`, and sent to the External Testers group and Apple's beta review
  (waits for Apple). The `## Open PRs` section left this file: GitHub is the only
  list of open PRs (`gh pr list`, or `/where`), so the file cannot go stale on it.
- Late 2026-11-12: merged #159, #160, #161 (closes #151-#153). Owner decisions: a guest's mid-upgrade name hold is
  10 minutes; after an account delete today's AI counter (counts only) stays until the next day. Deployed 14
  functions in 5 named groups (claimUsername, releaseUsername, acceptQuestionListShare, sendQuestionListShareReply,
  createQuestionListShare, deleteOwnAccountData, askAIQuestion, suggestAIAnswers, suggestQuickAnswers,
  generateQuestionPrompt, generateQuestionVariations, generateTrioQuestionSuggestions, suggestAnswerImages,
  saveSuggestedAnswerImage): all Successful, 32/32 services ready. Check loop PASS (run `2026-11-12-215651-3efb`):
  guest, upgrade, card + wand + Find Image, lists + share link, Trio ideas, both deletes; no server errors.
  Not driven: share receive (needs a second account). To look at: a question list may stay on the server after
  its owner deletes the account; one Find Image pick saved right after picking was not stored. #158 opened
  (Home scroll hides the Profile button).
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
 .
- verify-triq maintenance pass done (#156, run `2026-11-12-180550-18bb`): every feature driven, a new
  `features/question-lists.md`. Formal checks re-run in sync (#155). Possible bug to look at: after a Home
  scroll the Profile button and the tab bar leave the screen. A pending Trio question from the run is left on the server.

## Next step

1. Choose the next focus; candidate: the question-list cleanup on account delete. #158 (Home scroll hides
   Profile and shrinks the tab bar) is closed: the owner made both on purpose (2026-11-13).
2. Triage #168 (client writes of server-owned answer stats are refused by the rules): move each backfill to the
   server or delete the client write; also check the `BadgeModel` client transaction it names.

## Waits for the owner

- #166 (docs: apply the prompt audit's high-priority fixes) and #169 (formal: sync commits and line references
  after the #159, #160, #161 fixes): both green, both comment-and-Markdown only, but each changes a `.tla` model
  file, which "Safe merges" does not cover. Merge #166 first or second: they touch different lines.

- #139 (before release, check that 1 copy per function is enough for launch traffic): `ready-for-human`.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
