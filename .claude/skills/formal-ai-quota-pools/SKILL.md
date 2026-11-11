---
name: formal-ai-quota-pools
description: Model-check the server-side AI quota (the per-uid daily limit in aiUsageDaily and the project-wide guest/verified pools in aiUsageProjectDaily) with TLA+. Use before you merge any change to functions/aiUsageLimit.js, the aiCallable wiring in functions/index.js, functions/appCheckReplay.js, the aiUsageDaily deletion in functions/accountDeletion.js, or the aiUsageDaily / aiUsageProjectDaily rules in firestore.rules; or when someone asks whether a caller can get more AI calls than its limit.
---

# Formal check: AI quota pools

**Property.** No uid gets more AI provider calls on a UTC day than its per-uid daily limit
(`DAILY_LIMITS`), no project pool (`PROJECT_DAILY_LIMITS`, guest or verified) gets more provider
calls on a UTC day than its limit, and no call is refused while the uid or its pool has really spent
less than its limit. This must hold under concurrent calls, provider failures (attempts count, no
refund), client retries, UTC midnight, a guest who links and verifies an email mid-day, and account
deletion.

**Harm.** A break past the pool is a bill or a suspended Groq key for every user (ADR-0011); a
wrong refusal locks real users out of AI.

Read `docs/adr/0006-app-check-and-server-owned-ai-quota.md` and
`docs/adr/0011-project-wide-ai-pools-and-single-use-app-check.md` for why the quota looks like this.
The glossary is `CONTEXT.md`; it has no quota terms, so the model's names come from the code and the
ADRs: guest = anonymous sign-in, permanent account, guest pool / verified pool, attempt.

## Run

```sh
.claude/skills/formal-ai-quota-pools/run.sh            # about 30 s; optional arg: output folder
```

Needs `node`, `java` 11+ and, on the first run, the network: the script downloads `tla2tools.jar`
1.7.4 (sha256-pinned) to `~/.cache/tla2tools/1.7.4/`. Set `TLA2TOOLS=<jar>` to use another copy.

The script:

1. Prints a NOTE if a covered file changed after the sync commit (below).
2. Runs `extract-flags.mjs`, which reads three facts from the code and checks the shapes the model
   takes as fixed (one transaction for both counters, the day read once before it, the reset on another
   dayKey, the pool from `isGuestToken`, the `aiCallable` wrapping, the counter deletion, the
   `if: false` rules, no refund). Exit 2 means the code moved away from the model: read the message,
   then "When the code changed" below.
3. Runs TLC on four configs, checking every rule; when a rule breaks it drops that rule and runs again,
   so every rule gets a verdict.
4. Compares each verdict with the known findings. Exit 0: as expected. Exit 1: some verdict
   `CHANGED`.

Expected output today (sync commit below):

```
AIQuotaPools  UidWithinDailyLimit   BREAKS  as expected      (findings 1 and 2)
AIQuotaPools  PoolWithinDailyLimit  HOLDS   as expected
AIQuotaPools  NoWrongLockout        HOLDS   as expected
rollover      UidWithinDailyLimit   BREAKS  as expected      (finding 1)
rollover      PoolWithinDailyLimit / NoWrongLockout  HOLDS
deletion      UidWithinDailyLimit   BREAKS  as expected      (finding 2)
deletion      PoolWithinDailyLimit / NoWrongLockout  HOLDS
core          all three             HOLDS   as expected
```

`core` turns off UTC midnight and account deletion, so it still guards the per-uid check while
findings 1 and 2 stand. `rollover` and `deletion` each keep one of the two, so a fix to one finding
shows as `CHANGED (expected BREAKS)` on its own config. When you fix a finding, update
`known_breaks` in `run.sh` and the list below in the same PR.

## Reading a result

Read every TLC result with `/statechart` (spec `AIQuotaPools.tla`, view `view.mjs`, one of the
`chart-*.cfg` configs, or a `check.cfg` from the run's output folder). It tells a broken rule as its
shortest path of steps in plain words. `run.sh` prints the TLC action names of each path only.

A break is a real bug when you can replay its path on the real `consumeDailyQuota`, one call per
step: `replay.cjs` shows how (in-memory Firestore, one transaction at a time; run it with
`NODE_PATH=<a checkout>/functions/node_modules node .claude/skills/formal-ai-quota-pools/replay.cjs`
or after `npm ci` in `functions/`). If the path cannot happen in the code, the model is wrong: fix the
model and say so in the PR, never weaken a rule to make it pass.

## Known findings (both replayed on the real code by `replay.cjs`)

Both break the per-uid limit only. The pool rule holds in every config, so neither lets spend pass
the project pool.

1. **A call that read the clock before UTC midnight resets the counter after it.** `withDailyQuota`
   reads `now()` once, before `db.runTransaction`, and a transaction retry keeps that day. Steps:
   a guest at 5 of 5 on 2026-07-31 sends a call at 23:59:59 (it waits on the contended counter);
   another call at 00:00:00.1 commits first and writes `dayKey: "2026-08-01"`; the late call then
   reads a document whose `dayKey` is not its own, counts it as 0
   (`stored?.dayKey === dayKey ? … : {}`), passes, and writes `dayKey: "2026-07-31", count 1`. The
   guest gets 6 provider calls on 2026-07-31; the next call on 2026-08-01 resets again and wipes that
   day's count too. Each call that crosses midnight this way is one extra call, and the reset also
   wipes the uid's other groups (the whole `counts` map is rewritten).
2. **Account deletion resets the counter while the uid can still call.** `deleteOwnAccountData`
   deletes `aiUsageDaily/{uid}` before the Auth user. `onCall` verifies the ID token without
   `checkRevoked`, so the deleted uid's token keeps working for up to an hour (and if
   `deleteAuthUser` throws, the account stays). Steps: a guest uses 5 of 5, deletes the account, and
   sends 5 more calls on the same day with the same token. Low harm: a new guest uid is free anyway.

Not a finding, by design (ADR-0006, ADR-0011): a provider error costs the attempt; an unverified
email account keeps the permanent per-uid limit but draws from the guest pool; a guest who links an
email mid-day keeps the same uid and counter, so its day total is the permanent limit, not
guest + permanent.

## The model

`AIQuotaPools.tla`, one group (`aiQuery`; every group runs the same code). Steps:

| Model action        | Code |
| ------------------- | ---- |
| `SendCall`          | `aiCallable` → `withSingleUseAppCheck` → `withDailyQuota`: reads `now()` (`dayKeyFor`) and the token's `sign_in_provider` / `isGuestToken` |
| `QuotaTransaction`  | `consumeDailyQuota` + `nextProjectDocument`: one `db.runTransaction`, reads `aiUsageDaily/{uid}` and `aiUsageProjectDaily/{dayKey}`, refuses (`daily-limit`, `project-daily-limit`) or writes both. One atomic step, as Firestore serializes it |
| `ProviderCall`      | the handler in `index.js` calling `aiProviderProxy.js`; answer and failure end the same way (no refund) |
| `Midnight`          | the UTC day changes (`dayKeyFor`) |
| `LinkEmail`, `VerifyEmail` | the guest links an email (same uid, `sign_in_provider` not anonymous), then verifies it (`email_verified`) |
| `DeleteAccountData` | `accountDeletion.js`: `recursiveDelete(aiUsageDaily/{uid})`; the uid keeps calling |

Flags from the code (`extract-flags.mjs`): `UidRefusesAtLimit` (`if (used >= limit)` in
`consumeDailyQuota`), `PoolRefusesAtLimit` (same in `nextProjectDocument`), `ChargeBeforeProvider`
(`await consumeDailyQuota` before `handler(request)` in `withDailyQuota`).

Rules: `UidWithinDailyLimit`, `PoolWithinDailyLimit`, `NoWrongLockout` (plus `TypeOK`). The model's
truth comes from fields on each call (`passed`, `paid`, `wrong`), not from the documents the code
keeps.

**Bounds.** Limits scaled down: guest 1 / permanent 2 per uid, guest pool 2 / verified pool 2. Two
UTC days. The caller under study (`FirstUid`) starts as a guest, sends 3 calls, and may link, verify
and delete; a second caller of any account kind sends 1 call. About 730 000 states for the full
config.

**Left out.** `PROJECT_MINUTE_LIMIT` (same stale-key shape as finding 1 by reading:
`minuteCount` restarts when the stored `minuteKey` differs, so a late call can restart the minute;
not checked); App Check single-use (it refuses before the quota and touches no counter); the other
groups and their limits; the client's `users/{uid}/aiUsage` document (display only, ADR-0006); token
staleness (an old token only gives a lower limit or the guest pool); more than 3 calls, 2 callers or 2
days; Firestore outages and partial writes (the transaction is all or nothing).

## Charts

`charts/` holds the `/statechart` output for the three chart configs (one caller, no second caller):
`core` (2 calls, the whole graph, every rule holds), `rollover` (finding 1's path), `deletion`
(finding 2's path). The core chart hides no steps and has 34 arrows. Make them again with
`/statechart`, a new output folder, `view.mjs` and the matching `chart-*.cfg`.

## When the code changed

1. Run `run.sh`. If it exits 2, `extract-flags.mjs` names the shape that moved.
2. Read the diff of the covered code against the table above. If the model no longer describes the
   code, change the model (and `extract-flags.mjs`) first, then rerun.
3. Move the sync commit forward only after you confirmed that the model describes the code at the
   new commit, and say so in the PR.

## Coverage record

Covered: `functions/aiUsageLimit.js` (`consumeDailyQuota`, `nextProjectDocument`, `withDailyQuota`,
`isGuestToken`, `dayKeyFor`, `DAILY_LIMITS`, `PROJECT_DAILY_LIMITS`), `functions/index.js`
(`aiCallable`, `AI_FUNCTION_OPTIONS`), `functions/appCheckReplay.js` (`withSingleUseAppCheck`, order
only), `functions/accountDeletion.js` (`deleteOwnAccountData`, the `aiUsageDaily` delete),
`firestore.rules` (`aiUsageDaily`, `aiUsageProjectDaily`).

Sync commit: `2878987798d1e2eb70d686c54eaaf2730356a8ce` (2026-11-12). Proved at this commit: two
scratch breaks in `functions/aiUsageLimit.js` were caught and dropped: `used > limit` in
`nextProjectDocument` (`PoolWithinDailyLimit` CHANGED on all four configs) and calling the handler
before `consumeDailyQuota` (`UidWithinDailyLimit` CHANGED on `core`).
