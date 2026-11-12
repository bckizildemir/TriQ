# TriQ verification map

This directory is the maintained source for verifying what a user of TriQ sees. Read this index
before you drive the app, then use the matching feature file as the recipe. The harness is
`scripts/vt.sh` plus `axe` (the only driver, owner 2026-11-12) on the run's own fresh simulator; see
`../SKILL.md` for launch, doctor, the live-Firebase rules and cleanup.

## Baseline preconditions

- A run is open: `vt.sh start` → `vt.sh build` → `vt.sh install` → `vt.sh launch`, and
  `vt.sh doctor` exits 0. Every command below runs from the repo root; `vt` means
  `.claude/skills/verify-triq/scripts/vt.sh` — type that full path in each command.
- `<UDID>` is the run's device: the literal value in `/tmp/verify-triq.lock/udid`.
- The app was launched with no arguments. A fresh device has no session, so the app opens on the
  sign-in screen. Every other feature needs [Guest onboarding](./guest-onboarding.md) done first.
- The app talks to live Firebase (`ttbp-9d652`). Each feature names its live-data class. A feature
  marked **writes live** or **AI call** needs the owner's yes for that action before the drive.

## Driving conventions

- Tap with `vt tap <axe selector>`; it exits 1 when the screen did not change after two taps. Then
  read `vt ui`. A tap that writes live uses `vt tap --once` (no second tap).
- Match by identifier (`vt tap --id …`) first, by label (`--label`) with `--element-type` second.
  Coordinates (`axe tap -x … -y … --tap-style physical --udid <UDID>`) only when an element has neither.
- The tabs are `RadioButton`s; their identifiers are SF Symbol names (`lanyardcard.fill`,
  `medal.star.fill`, `sparkles`). Labels: Home | Ana Sayfa, Best Of | En İyiler, Trio | Trio.
- After each action, read `vt ui` and check the expected element before the next action.
- Live content (question text, categories, counts) changes daily. Assert on identifiers and
  structure, not on text from the database.

## Features

Status: a feature is **proved** only after a live run drove it as written. "(unproved draft)" means
the file was written from source and nobody has driven it yet.

| Feature | Live-data class | Status |
| --- | --- | --- |
| [Guest onboarding](./guest-onboarding.md) | writes live (one anonymous Auth user + `users/<uid>`; free; standing yes); the sign-in form reads live (`resolveUsername`) | proved 2026-10-21; sign-in form and legal links 2026-11-12 |
| [Home feed](./home-feed.md) | reads live | proved 2026-10-21; the fold and the scrolled chip tap proved 2026-10-28; re-proved 2026-11-12 |
| [Guest favorites](./guest-favorites.md) | local only for a guest; the strip upgrade and the signed-in star write live | proved 2026-10-21, cap included; strip upgrade and signed-in star 2026-11-12 (cap not re-driven) |
| [Question card](./question-card.md) | AI calls (open: `suggestQuickAnswers`, wand: `suggestAIAnswers`); live reads (`suggestAnswerImages`); writes live to save (`saveQuestionAnswers`, `saveSuggestedAnswerImage`) | proved 2026-10-21, save included; wand, Find Image, Save and Close 2026-11-12 |
| [Profile and guest upgrade](./profile.md) | reads live; the upgrade and Delete Account write live | proved 2026-10-21; delete (guest and account) 2026-11-11 and 2026-11-12 |
| [Trio question composer](./trio-composer.md) | AI call (ideas) and writes live (publish); a permanent account only | proved 2026-10-21; re-proved 2026-11-12 |
| [Question lists](./question-lists.md) | writes live (`createQuestionList`, `setQuestionInList`, `updateQuestionList`, `deleteQuestionList`); an account only | proved 2026-11-12; receiving a shared list verified-unreachable |

[Change map](./changes.md): which journeys a changed function, rules path or screen needs (the
check loop in `../SKILL.md`).

Order for a full pass: guest onboarding, Home feed, guest favorites, question card, profile, Trio as
guest, then the upgrade of the run's guest to the run's own account (standing yes; see `../SKILL.md`;
the favorites strip's "Keep them" is a good entry), the account part of Home (star, list button),
Trio, question lists, and last Delete Account (account, then a second guest for the guest delete).

## Not reachable without a harness

These states need a `-ui-test-*` harness flag or live data that a fresh run does not have. The
skill does not use the flags, so a run reports them as not verifiable:

- the AI daily-limit state (`DAILY_LIMITS` in `functions/aiUsageLimit.js`); the seeded Trio draft;
- a shared question list received from a link (needs a second account that shares one; see
  [Question lists](./question-lists.md));
- a published Trio question in the app: it stays `pending` and no screen shows it until a moderator
  approves it;
- Best Of Today rankings on a fresh day: on 2026-10-21 and 2026-11-12 the Today tab started with "No
  Rankings Yet" (it ranks a question once someone saved answers to it; All Time has rankings).
