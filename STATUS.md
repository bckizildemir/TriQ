# TriQ status

The hand-off file. Read it at session start; update it before the final report.
Every PR or issue number goes with a plain title.

## Focus

Finish the answer image viewer (owner, 2026-11-17), in this order. Done 0/3.
1. Gesture tool spike: AXe 2.0.4 `tap --count 2`, `gesture double-tap`, `gesture pinch` and a fast swipe, 10 runs
   each on a throwaway simulator; update verify-triq with what works (research:
   `iOS Dev/research/2026-11-17-simulator-test-tools.md`, outside the repo, sections 5 and 7). Needed to prove item 2.
   **Blocked: Google Cloud billing is off (found 2026-11-18).** The second try, from the owner's home network, ran
   `~/verify-evidence/triq/2026-11-18-000939-2aa1`: Find Image and the AI quick answers both fail with HTTP 500
   "billing is disabled for this project"; `gcloud billing accounts describe 01310F-AFB3AB-5E9E3D` prints
   `open: False`. The company-network reason below was wrong: Find Image calls Pexels from the Cloud Function, not
   from the Mac. Start trigger: the owner reopens or replaces the billing account (a spend decision, owner only);
   then re-run the spike. The earlier note, kept for the syntax: First try, BLOCKED, run
   `~/verify-evidence/triq/2026-11-17-133857-097b`. AXe 2.0.4 syntax, read from `--help`:
   `axe tap -x X -y Y --count 2 --tap-style physical --udid U`; `axe gesture double-tap -x X -y Y [--interval 0.1]`;
   `axe gesture pinch -x X -y Y --scale 2 [--radius R --duration 0.6 --delta 5]` (scale < 1 zooms out); fastest
   swipe `axe swipe ... --duration 0.05 --delta 5` (no velocity flag). Memory, same run: 4 slim clones at once kept
   at least 33% free on the 16 GB Mac (one with the app, no build running), so `SLIM_SIM_MAX=4` is now set in
   `~/.claude/settings.json`.
2. #188 (answer image viewer: four known gesture limits): fix each, or ask the owner to keep it, one by one.
3. #186 (answer image shows late after a Find Image pick and on the Home card).

Previous focus, done 1/1: #168 (client writes of server-owned answer stats are refused by the security rules),
chosen by the owner 2026-11-16, fixed with option A in #173 (merged 2026-11-16, issue closed). The triage below is
kept for reference; it describes `origin/main` at `44e8551`, before the fix:
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

2026-11-17

Last session:
- 2026-11-17 (latest): #184 (pan a zoomed-in answer image) and #183 (shared Motion tokens) merged, squash, owner's
  yes for each, in that order; #183 resolved its conflict with #184 by a merge commit (tokens only where the value
  is identical; #184's new springs stay literal). Proof of both together: PASS, run
  `~/verify-evidence/triq/2026-11-17-113514-1273` (zoom, pan inside edges, tap while zoomed does nothing, back to
  1×, swipe-down close, star, tabs, carousel, launch fade). Not proved: pinch, the toast, a fast sideways flick at
  1×. Known limits of #184, OPEN, not accepted (the merge question left them out; the owner found out later):
  tracked in #188 (at 1× a drag over 100 pt in any direction can close the viewer, older than #184; pinch and
  pan don't run together; grabbing mid-glide jumps to the glide's end; gestures start only on the image). AXe
  upgraded to 2.0.4 on the owner's yes; XcodeBuildMCP points at it through `XCODEBUILDMCP_AXE_PATH` in
  `~/.claude/settings.json`. #186 opened (answer image shows late after a Find Image pick and on the Home
  card; probably older). Research on simulator test tools:
  `iOS Dev/research/2026-11-17-simulator-test-tools.md` (outside the repo): AXe 2.0.4 adds double tap and pinch.
- 2026-11-16/17: the parked audit leftovers, started on the owner's go after the usage reset.
  - #182 (verify-triq: simulator tool traps) merged (docs). Plans 001-010 marked DONE in
    `animation-audits/TriQ-2026-11-16/plans/README.md` (outside the repo).
  - #183 (shared Motion tokens, audit finding 11): 18 tokens in `TTB/Utilities/Motion.swift`, values unchanged at
    all 23 sites (swift-reviewer checked each), `MotionTests` compare real values. CI green. Waits for the owner's
    merge. No simulator run: no visible change.
  - #184 (pan a zoomed-in answer image; owner's yes from #177): double tap 1×↔2.5×, pinch keeps its zoom up to 5×,
    zoomed one-finger drag pans inside the screen edges with a glide, never closes; black tap closes at 1× and does
    nothing while zoomed. Three fix rounds after two swift-reviewer reviews and simulator runs. Final proof PASS on
    c34e1ec (`~/verify-evidence/triq/2026-11-16-235701-1e8a`). Not proved: pinch (one-finger tool). Waits for the
    owner's merge. #183 and #184 both touch `QuestionCardExpandedView.swift`; whichever merges second rebases.
  - Lesson: four simulator runs read "double tap does nothing" as an app bug; it was the tool (`axe tap` pairs are
    no double tap). A control run on the old commit found it. Recorded in verify-triq Gotchas.

Last session:
- 2026-11-16 (latest): the owner approved the rest of the 2026-11-16 animation audit (outside the repo,
  `iOS Dev/animation-audits/TriQ-2026-11-16/`). Three PRs, each reviewed, fixed after review, CI green and proved
  on the simulator (iOS 27); none merged yet (app code: owner's merge):
  - #177 (answer image viewer zooms out of its thumbnail, a flick closes it, the zoom eases back; plans 004 + 008).
    Runs `2026-11-16-151446-0cd5`, `2026-11-16-154714-24ec`. Not proved: pinch (axe has one finger), iOS 18.5.
    Gap found, not in scope: a zoomed-in image cannot be panned (no pan code).
  - #178 (Trio suggestions keep their full row height while they type in; plan 007). Run `2026-11-16-152838-22f2`.
    The run's account `verifytriq-152838-22f2` stays on the server for pre-release cleanup.
  - #179 (onboarding steps slide in the direction you move, softer Profile press, calmer page dots, AI disclosure
    stagger; plans 009, 010, findings 12, 13). Runs `2026-11-16-161722-2f1c`, `2026-11-16-162736-2e7c`.
  - All three merged later the same day (owner's yes), squash, order #178, #179, #177.
  - Left from the audit: finding 11 (shared Motion tokens), after #177-#179 merge, since it touches their files.
- 2026-11-16 (later, owner's yes for each after `/code-review`): merged, squash, in this order: #174 (five motion
  fixes from the 2026-11-16 audit; review findings checked by a judge, none blocking), #173 (fix #168, see below;
  the review found one more refused write, `ensureBadgeUserDocument`, removed before merge), #175 (a tapped
  question card zooms into the answer editor; branch updated after #173/#174, CI green). #175 proof: with typed,
  unsaved text a swipe-down keeps the editor open with the text; with no text it closes. PASS on iOS 27.0
  (`~/verify-evidence/triq/2026-11-16-102231-1fba`) and iOS 18.5 (`2026-11-16-103258-2f95`), fast flick only
  (`axe swipe ... --duration 0.25 --delta 5`); a slow interactive drag was not proved. Open follow-ups (minor, no
  issue yet): #174 plays no save haptic in the iOS 27 dismissal dialog's Save path; #175 `DraftDismissalStyle`
  `dialogAvailable: false` is never passed by app code. No deploy.
  Check loop after the merges (range `b11da3c..4423778`): PASS, run `2026-11-16-104818-466d` (iOS 27.0, English):
  launch logo hand-off with no flicker, card zoom open/close, Favorites remove animation with no gap, Profile badges
  screen loads ("0 / 30", no error) on a permanent account; server log clean. Not proved: haptics (simulator), the
  absence of the sign-in backfill (only that sign-in works), answer save. Live writes: one guest and the account
  `verifytriq-104818-466d` (not deleted; clean before release).
- 2026-11-16 (#168 fix, option A, merged as #173): PR deletes the badge backfill at sign-in, the `totalAnswered` migration write in
  `ProfileModel`, and the dead `BadgeModel` transaction paths with their `BadgeStoring` methods, plus
  `BadgeModel.ensureBadgeUserDocument` (a refused merge write that made the badge screen show `badge.error.load`
  for an old user document), `AnswerStreakCalculator`, `BadgeProgressCalculator` and two unused strings. Swift only,
  no rules change, no deploy, no simulator run.
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

1. Focus item 1, the gesture tool spike, once the owner is off the company network (see Focus).
2. After the focus: release readiness (#139, test account cleanup, the question-list cleanup on account delete). #158 (Home scroll hides Profile and shrinks the
   tab bar) is closed: the owner made both on purpose (2026-11-13).

## Waits for the owner

- #188 (the four image viewer limits): a keep-or-fix answer per limit, asked when focus item 2 reaches it.
- #139 (before release, check that 1 copy per function is enough for launch traffic): `ready-for-human`.
- #21, #22 (Swift 6 stages 5a/5b, investigate then decide) and #44 (keyboard stays up under the image menu, flaky UI test): `ready-for-human`.
- #68 (run the UI tests in CI): needs a grilling round.
