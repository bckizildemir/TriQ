---
name: formal-guest-upgrade-identity
description: Model-check who holds a username while a Guest becomes a permanent account (AuthModel.linkAnonymousAccount) or a new user signs up (AuthModel.signUp), with TLA+ and a replay against the real functions/usernameRegistry.js. Use when you change linkAnonymousAccount, signUp, deletePartiallyCreatedAccount, UsernameService claim/release, or claimUsername/releaseUsername in functions/usernameRegistry.js, or when a username looks taken by nobody, shown twice, or missing after an upgrade.
---

# formal-guest-upgrade-identity

**The promise.** A username belongs to exactly one account someone can use, and the profile
shows a username only while its account holds it; a Guest's upgrade attempt either finishes with the
account holding the chosen name, or leaves the Guest exactly as it was.

**The harm when it breaks.** A name gets stuck on an account nobody can sign in to, so nobody can
ever take it; or two people show the same name; or a person who just upgraded has no username.

Terms follow `CONTEXT.md` (Guest, upgrade) and ADR 0012 (linking a Guest keeps the uid).

## Files

| File | What it is |
| --- | --- |
| `GuestUpgradeIdentity.tla` | The model. Each action names the code line it stands for. |
| `GuestUpgradeIdentity.cfg` | The rules TLC checks. |
| `view.mjs` | The words for the `/statechart` chart and report. |
| `replay-server.mjs` | Replays each bug path's server calls against the real `functions/usernameRegistry.js`, in memory. Needs only `node`. |
| `check.sh` | The one command: model check, compare with the known findings, server replay. |
| `charts/` | `chart.mmd`, `report.md`, `tlc.out` from the last `--save` run. |

## Run

Load the `/statechart` skill; it says where its script is and installs TLC and Java on first use.
Then, from the repo root:

```sh
STATECHART=<the /statechart script> .claude/skills/formal-guest-upgrade-identity/check.sh          # check
STATECHART=<the /statechart script> .claude/skills/formal-guest-upgrade-identity/check.sh --save   # also refresh charts/
```

About 20 seconds, 193 model states. Exit 0: exactly the known findings break, the holding rule
holds, and every finding still reproduces on the server. Exit 1: something changed (read below).
Exit 2: the tools did not finish; TLC killed with exit 143 under machine load is a reason to run
again, not a result.

Read every result with `/statechart`: each broken rule is a numbered shortest path in plain words.
Show `charts/chart.mmd` as a mermaid block. The chart hides the "app is killed" arrows (each lands
where a "saving fails" or "answer lost" arrow already lands); the model still checks them.

## Rules

| Rule | Plain words | At the sync commit |
| --- | --- | --- |
| `NameStaysWithItsHolder` | A claim never takes a name from the account that holds it. | holds |
| `NoOrphanAfterUpgrade` | A name the Guest claimed never ends on an anonymous user nobody can reach. | **breaks** (finding 1) |
| `FailedUpgradeLeavesNoName` | An upgrade that did not finish leaves the Guest holding no name, showing the placeholder. | **breaks** (finding 1) |
| `ShownNameIsHeld` | A profile shows a name only while its account holds it. | **breaks** (finding 2) |
| `UpgradedAccountKeepsItsName` | An account that became permanent holds the name it chose. | **breaks** (finding 3) |
| `NoOrphanAfterSignUp` | A failed sign-up never leaves its name on the deleted account. | **breaks** (finding 4) |

## Findings (open; do not weaken a rule to make it pass)

1. **Answer lost on the first claim.** Guest taps Create account → `claimUsername(isAnonymous: true)`
   (AuthModel.swift:350) commits, but the app gets an error (timeout, lost answer) or is killed
   before `linkAccount`. That throw is outside the inner `do/catch`, so `releaseUsername` never runs.
   The Guest stays a Guest whose profile shows the chosen name and holds it. If the Guest then signs
   out, the anonymous user is out of reach and the name is held forever: nobody can claim it.
2. **Profile read fails.** `profileSnapshot` (:348) is `try?`, so a failed read gives `nil`. Then
   the name is saved, linking fails (email in use, weak password, offline), and `releaseUsername`
   (:365) runs with no `restoreUsername`. It deletes `usernames/<name>` but patches no username, so
   `users/<uid>.username` still shows the name. Someone else can now claim it; two people show it.
3. **Link succeeds, the rest fails.** `linkAccount` (:357) succeeds, then `forceRefreshIDToken`
   (:358) or the second claim (:359) throws. The shared `catch` releases the name and restores the
   Guest profile (`Guest User`, `isAnonymous: true`) on an account Firebase Auth now treats as
   permanent. The person sees an error although the email is now linked, and the
   account has no username; the name is free for anyone.
4. **Sign-up claim answer lost.** `signUp`: `createUser` (:275), then `claimUsername` (:277)
   commits but the app gets an error. `deletePartiallyCreatedAccount` (:283 →
   `LiveAuthUserDocumentManager.deleteUserAndAuth`) deletes `users/<uid>` and the Auth user, not
   `usernames/<name>`. No server trigger removes it, so the name is held by a deleted account forever.

`replay-server.mjs` runs each finding's server calls through the real `claimUsername` /
`releaseUsername` and prints REPRODUCES; it shows the client branch it stands for in a comment.

## What the model covers, and what it leaves out

One device, one username N, three uids: the Guest `g` (kept by the link, ADR 0012), the sign-up
user `s`, and another person `o` on another device. Each `claimUsername` / `releaseUsername` is one
Firestore transaction, so it is one step; "answer lost" is that step committing while the client
takes its `catch`. Each `await` in AuthModel is a point where the app can be killed. Firebase Auth
calls (`linkAccount`, `forceRefreshIDToken`, `createUser`) succeed or fail as one step.

Left out: a second name (the rename path in `claimUsername` that deletes the old entry); Edit Profile
renames; account deletion (`functions/accountDeletion.js` deletes `usernames` where `uid` matches, so
it frees the name); `resolveUsername` sign-in; the `isAnonymous` field on `users/` and `usernames/`
(no code reads it; the server uses the token's provider); guest favorites migration and the list
stores (ADR 0012), which follow the uid and the ID token and were not modelled here; a partial
`deleteUserAndAuth` (document deleted, Auth delete fails). One sign-up per run.

## Coverage record

Sync commit: `2878987` (origin/main, 2026-11-12). The model describes these as of that commit:

- `TTB/Models/AuthModel.swift`: `linkAnonymousAccount` (:328-378), `signUp` (:247-294),
  `deletePartiallyCreatedAccount` (:380), `signOut` effects via `ProfileModel.signOut`.
- `TTB/Models/AuthModelDependencies.swift`: `LiveAuthUserDocumentManager.profileSnapshot`,
  `deleteUserAndAuth`.
- `TTB/Services/UsernameService.swift`: `claimUsername`, `releaseUsername` (errors swallowed).
- `functions/usernameRegistry.js`: `claimUsername`, `releaseUsername`.

To see whether the model may be stale:

```sh
git diff 2878987 -- TTB/Models/AuthModel.swift TTB/Models/AuthModelDependencies.swift TTB/Services/UsernameService.swift functions/usernameRegistry.js
```

Move the sync commit forward only after you read that diff and confirm the model still describes
the code (or you changed the model to match). Line numbers in the spec comments move with it.

## When the result changes

- **A known finding stops breaking** after a code fix: change the model action that stands for the
  changed code (for example a release in the `Claim1CommitsAnswerLost` branch, or a server trigger
  that frees names on Auth deletion), run again, and confirm the rule now holds. Then remove it from
  `KNOWN_FINDINGS` in `check.sh` and from the Findings list, and flip its replay in
  `replay-server.mjs` to a `holds(...)` check against the fixed code.
- **A new rule breaks**: replay its path step by step in the code first. If the code does what the
  path says, it is a bug: report it, do not edit the rule. If the code cannot do a step, the model is
  wrong there: fix that action and say why in its comment.
- **`replay-server.mjs` prints BROKEN or GONE** without a model change: the server code changed under
  the model. Read the diff above and bring the model in line.

## How this check was proven

At `2878987` the server check at `functions/usernameRegistry.js:96` was disabled on a scratch copy
(`if (false && ...)`, so a claim could take a name someone else held), and `FreeFor` in the spec was
set to `TRUE` to match. `check.sh` exited 1: `NameStaysWithItsHolder` broke in 3 steps (Guest taps
Create account → someone else takes the name → the Guest's claim saves it anyway), the replay
printed BROKEN for it, and finding 4's replay printed GONE. With both scratch changes dropped, it
exited 0 with only the four known findings.
