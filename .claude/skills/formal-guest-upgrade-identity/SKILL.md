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

Terms follow `GLOSSARY.md` (Guest, upgrade) and ADR 0012 (linking a Guest keeps the uid).

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

About 20 seconds, 193 model states. Exit 0: no rule breaks and every replay path holds on the server. Exit 1: something changed (read below).
Exit 2: the tools did not finish; TLC killed with exit 143 under machine load is a reason to run
again, not a result.

Read every result with `/statechart`: each broken rule is a numbered shortest path in plain words.
Show `charts/chart.mmd` as a mermaid block. The chart hides the "app is killed" arrows (each lands
where a "saving fails" or "answer lost" arrow already lands); the model still checks them.

## Rules

| Rule | Plain words | Now |
| --- | --- | --- |
| `NameStaysWithItsHolder` | A claim never takes a name from a permanent account that holds it. | holds |
| `NoOrphanAfterUpgrade` | A name on a Guest nobody can reach again (signed out) can be taken over by the next claim. | holds |
| `FailedUpgradeLeavesNoName` | An upgrade that did not finish leaves the Guest holding no name; after a kill between claim and link the name stays reclaimable. | holds |
| `ShownNameIsHeld` | A profile shows a name only while its account holds it. | holds |
| `UpgradedAccountKeepsItsName` | An account that became permanent holds the name it chose. | holds |
| `NoOrphanAfterSignUp` | A failed sign-up never leaves its name on a deleted account for good. | holds |

## Findings (issue #151, fixed; the replay checks each fix on the real server code)

1. Answer lost on the first claim: the first claim is inside the client's do/catch, so `releaseUsername`
   runs; if the app is killed instead, `claimUsername` takes the name over from an anonymous holder whose
   claim is older than 10 minutes (Firebase Auth says the holder is anonymous) and resets its profile.
2. Profile read fails: the read is no longer `try?`; a failure stops before any claim. `releaseUsername`
   also puts the placeholder on a profile that still shows the released name.
3. Link succeeds, the rest fails: nothing is released after the link. The token refresh is logged, claim 2
   is tried twice; the account keeps the name it holds.
4. Sign-up claim answer lost: `signUp` releases the name before deleting the account; if that fails,
   `claimUsername` takes the name over from a holder whose Auth user is gone (a missing users document alone is not enough).

Residual (not modelled as a break): a Guest killed between claim and link keeps showing the chosen name
until someone reclaims it or the Guest tries again.

`replay-server.mjs` runs each path through the real `claimUsername` / `releaseUsername` and prints HOLDS.
