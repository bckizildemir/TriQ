# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Focus

#168 (client writes of server-owned answer stats are refused by the security rules), chosen by the owner
2026-11-16. The owner chose option A; the fix PR (branch `fix/168-drop-client-stat-writes`, "Closes #168") deletes
writes 1-3 below and waits for the owner's review. Triage as found on `origin/main` at `44e8551`:
- The rule: the `users/{userId}` owner update allowlist (`firestore.rules:202-207`) lists no stats field
  (`totalAnswered`, `dailyAnswers`, `weeklyAnswers`, `completedQuestionIds`, `categoryAnswers`, `currentStreak`,
  `badgeProgress`, `unlockedBadges`). The server writes them (`functions/questionMutations.js:204-242`).
- Write 1, live: `QuestionService.backfillBadgeProgressIfNeeded` (`TTB/Services/QuestionService.swift:327`, write
  `setData(updates, merge: true)` at `:422`). `AuthModel.handleAuthenticatedUser` awaits it at
  `TTB/Models/AuthModel.swift:166`, before `authState = .authenticated`. It runs for every permanent account whose
  doc has `totalAnswered == 0`, no `completedQuestionIds` or no `badgeProgress`: a new user with no answers pays one
  `userAnswers` collection-group query per sign-in; a user with answers also reads the whole `questions` collection,
  then the write is refused. What the user sees: no error (the catch only logs "Badge backfill error"); sign-in
  waits for those reads every time; the stats and badges never get the backfill.
- Write 2, live: `ProfileModel.applyStatistics` (`TTB/Models/ProfileModel.swift:264-268`) writes `totalAnswered`
  from the legacy `totalAnswers` with `try?`. Refused, error dropped. The screen still shows the legacy total, so
  the user sees nothing; the doc is never migrated. The server already reads `totalAnswered || totalAnswers`
  (`functions/questionMutations.js:204`), so the next answer fixes the total anyway.
- Write 3, dead code: `BadgeModel.checkBadgeProgress` (`TTB/Models/BadgeModel.swift:157`, writes at `:210`, `:217`)
  and `incrementAnswerCountIfNeeded` (`:242`, write at `:283`) have no caller in `TTB/` or `Tests/` (only
  `:309`, inside `incrementAnswerCountIfNeeded`). Nothing refused at run time; delete them.

Fix options (no rule widening: a user could then forge their own stats):
- A (recommended), delete the client writes, as #126 (stop patching server-owned stats on old user documents)
  did for #116: remove `backfillBadgeProgressIfNeeded` and its `badgeBackfillService` wiring (`QuestionService`,
  `AuthModel`, `AuthModelDependencies`, `UITestAuthMocks`, their tests), the `setData` in
  `ProfileModel.applyStatistics` (keep the legacy read), and the dead `BadgeModel` transaction paths and the
  `BadgeStoring` methods only they use. Swift only, no deploy. Risk low: an old account with missing
  `completedQuestionIds`/`categoryAnswers`/badges keeps them missing until it answers again; it never got them
  before either. Also makes sign-in faster. Size: small, mostly deletions, one PR.
- B, move the backfill to the server: a callable (or a one-time Admin SDK migration) that recomputes the stats
  from `userAnswers`, plus the client call. Needs a Cloud Functions deploy, or a script that writes live
  Firestore: both need the owner's yes. Risk medium: new server code, idempotency, read cost of the whole
  `questions` collection, abuse limits. Size: medium. Worth it only if real accounts lack the fields; nobody has
  counted them (a read-only query of live `users` would tell).

Previous focus, done 3/3: #151 (guest upgrade username) fixed in #161; #152 (old share link; late reply) fixed in
#159; #153 (AI daily limit at midnight / after delete) fixed in #160.

## Last updated

2026-11-16

Last session:
- 2026-11-16 (#168 fix, option A): PR deletes the badge backfill at sign-in, the `totalAnswered` migration write in
  `ProfileModel`, and the dead `BadgeModel` transaction paths with their `BadgeStoring` methods. Swift only, no
  rules change, no deploy, no simulator run. Left for its own issue: `BadgeModel.ensureBadgeUserDocument` still
  patches default stats onto an existing pre-stats document when the badge screen loads (refused; the screen
  shows `badge.error.load`), first noted in #126.
- 2026-11-16: merged #166 (docs: apply the prompt audit's high-priority fixes, `983afde`) and #169 (formal: sync
  commits and line references after the #159/#160/#161 fixes, `44e8551`), squash, owner's yes for both. Owner chose
  #168 as the focus; triage above. No build, no deploy.
- 2026-11-14 (verification upkeep, finished): #170 (docs: one place for the command that re-runs all formal checks
  and the check loop) merged. The three formal checks ran again on the branch of #169 (formal: sync commits and line
  references after the fixes): each exits 0, no `NOTE`, no broken rule. #169 and #166 stay open for the owner
  (see below). #168 (client writes of server-owned answer stats are refused by the rules) was checked against
  `origin/main` at `09a6029`: both writes it names still exist.
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

1. #168: the owner reviews and merges the option A PR. Then decide on `BadgeModel.ensureBadgeUserDocument` (see
   Last session).
2. Later candidate: the question-list cleanup on account delete. #158 (Home scroll hides Profile and shrinks the
   tab bar) is closed: the owner made both on purpose (2026-11-13).

## Waits for the owner

- #168 fix PR (option A, delete the client writes): review and merge.
- #139 (before release, check that 1 copy per function is enough for launch traffic): `ready-for-human`.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
