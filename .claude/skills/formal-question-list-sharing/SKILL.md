---
name: formal-question-list-sharing
description: TLA+ model check of question list sharing (share links, accept, disable, regenerate, revoke, leave, reply) in functions/questionListShares.js and the questionListShares rules in firestore.rules. Use when a change touches those callables, the share or recipient rules, or the order of share calls in QuestionListShareService.swift / SharedQuestionListViews.swift, or to see the owner's "share a list" flow as a chart.
---

# Formal check: question list sharing

A Shared Question List (CONTEXT.md) is a snapshot an owner shares through a Share Link; Recipients
accept it, reply to it, and leave it; the owner disables, regenerates or revokes it. Each callable
runs on the server, and the server is the source of truth. Several callables are not one
transaction, so their steps can interleave with another person's. Tests run one call at a time and
do not reach those interleavings. This model does: TLC tries every order of the steps.

## What it checks

`QuestionListSharing.tla` models one owner, one share and the recipients in the config. Each action
is one indivisible step of the real code (a Firestore transaction, or one awaited read or write of a
callable that has no transaction); the comment on each action names its lines.

| Rule (INVARIANT) | The promise | Where it comes from |
|---|---|---|
| `DisabledLinkAdmitsNoOne` | No one gets in while the link is turned off. | CONTEXT.md "Share Link" |
| `ReplacedLinkAdmitsNoOne` | No one gets in through a link the owner has regenerated away. | Regenerate Link exists to kill a link that reached the wrong person |
| `RevokedShareStaysClosed` | After a revoke, no recipient can read the shared list (snapshot and owner answers). | CONTEXT.md "Revocation", ADR 0001, firestore.rules `isAcceptedShareRecipient` |
| `RecipientCapHolds` | Accepted recipients never exceed `recipientCap`. | CONTEXT.md "Share Link" |
| `NoReplyAfterLeavingOrRevocation` | No reply lands for the owner from someone who removed the list or was revoked. | App copy on Remove Shared List: "The owner will no longer see future replies from you." |

QLS:n below means line n of `functions/questionListShares.js` at the sync commit.

Bounds: `QuestionListSharing.cfg` = owner + 2 recipients, one regenerate (`MaxCode = 2`),
`Cap = 1` so the cap can bind; about 205,000 states, about 15 s. `Chart.cfg` = one recipient, and
no exploring past a saved reply (`SmallChartBound`), for the chart.

## Known findings (sync commit below)

1. `ReplacedLinkAdmitsNoOne` breaks. Owner shares, sends link 1. Recipient opens link 1 and taps
   Accept. `acceptQuestionListShare` finds the share by `shareCode` outside its transaction
   (QLS:100). Owner taps Regenerate Link (link 2 live). The accept transaction re-reads `status`
   and `isLinkEnabled` but never compares `shareCode`, so the recipient joins through the dead
   link 1. Same with Disable then Regenerate in the gap. Harm: a link the owner regenerated
   because it leaked can still let in the person who had it, who then reads the owner's answers.
2. `NoReplyAfterLeavingOrRevocation` breaks. Recipient taps Send Answers;
   `sendQuestionListShareReply` checks share status and recipient status in two plain reads, then
   writes later with no transaction (QLS:291-311). Recipient taps Remove Shared List (or the owner
   taps Revoke Share) in between; the reply is still saved with `unreadByOwner: true`. Harm: the
   owner sees a new reply from someone who left, against the app's promise. This is
   QUESTION_LIST_SHARING_AUDIT.md finding 4, now with a path.

`replay/findings.replay.js` replays both paths on the real callables (fake Firestore from
`functions/questionListShares.test.js`); `check.sh --replay` runs it.

## Run it

Load the `/statechart` skill first: it says where its script is on this machine, and how to read
its report. Then, from the repo root:

```sh
STATECHART=<statechart script> .claude/skills/formal-question-list-sharing/check.sh            # the check
STATECHART=<statechart script> .claude/skills/formal-question-list-sharing/check.sh --charts   # + redraw charts/
STATECHART=<statechart script> .claude/skills/formal-question-list-sharing/check.sh --replay   # + replay findings (needs functions/node_modules)
```

The first `/statechart` run installs TLC and Java with mise and needs the network.

Exit codes: 0 only the known findings break; 1 a new rule breaks; 3 a line the model relies on is
gone from the code; 4 a known finding no longer breaks; 2 the tool could not run. Read every result
with `/statechart`: the report gives each break as its shortest path of steps.

`charts/chart.mmd` is the owner's "share a list" flow (one recipient), with the bug paths marked;
`charts/report.md` is its report. The chart hides some arrows; `view.ts` lists them.

## Tell a real bug from a modelling error

On a new break, replay the path against the code, one action per step, in the order the report
gives: as a test in the style of `replay/findings.replay.js` (hook the fake db between two awaits).
If the code does not do what the step says, the model is wrong: fix the action, not the rule. Never
weaken a rule to make it pass.

## Keep it in step with the code

Coverage (each action's comment gives the lines):

- `functions/questionListShares.js`: `createQuestionListShare`, `previewQuestionListShare`,
  `acceptQuestionListShare`, `disableQuestionListShare`, `regenerateQuestionListShareLink`,
  `revokeQuestionListShare` / `revokeShareRef`, `leaveQuestionListShare`,
  `sendQuestionListShareReply`, `markQuestionListShareReplySeen`, `shareIsClaimable`.
- `firestore.rules`: `match /questionListShares/{shareId}` read rule (`isAcceptedShareRecipient`).
- `TTB/Views/Main/SharedQuestionListViews.swift`: the order preview -> Accept, and that Remove
  Shared List stays enabled while Send Answers is in flight.

Sync commit: `2878987798d1e2eb70d686c54eaaf2730356a8ce` (2026-11-12).

`check.sh` fails with exit 3 when a line the model stands on is gone (`anchor` lines in the script),
and prints a NOTE when a covered file changed since the sync commit. Then: re-read the changed
code, change the actions to match (one action per transaction or per awaited write), update the
anchors, run, and move the sync commit forward only after you confirm the model describes the code
at the new commit. When a fix lands for a known finding, the run exits 4: confirm, remove the rule
from `KNOWN` in `check.sh` and its test from `replay/`, and move it out of "Known findings".

## Left out

- The answer snapshot itself: no callable after `createQuestionListShare` writes `questionIds` or
  `ownerAnswerSnapshots` (read the code); the model has no list edits.
- "Recipients do not see other recipients": a static property of the rules and of what the share
  document holds, covered by `functions/firestoreRulesStatic.test.js` and the rules emulator tests,
  not an interleaving.
- The client: `SharedQuestionListStore` listeners, caches and stale screens; App Check and quotas;
  `revokeSharesForSourceList` (list deletion, which runs the same `revokeShareRef`); the owner name
  refresh write in preview; more than one share; more than one regenerate.
- A Firestore transaction is treated as atomic and serializable, as Firestore promises.
