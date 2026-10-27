# TriQ verification map

This directory is the maintained source for verifying what a user of TriQ sees. Read this index
before you drive the app, then use the matching feature file as the recipe. The harness is
`scripts/vt.sh` plus `axe` (or xcodebuildmcp UI tools) on the run's own fresh simulator; see
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
| [Guest onboarding](./guest-onboarding.md) | writes live (one anonymous Auth user + `users/<uid>`; free; standing yes) | proved 2026-10-21 |
| [Home feed](./home-feed.md) | reads live | proved 2026-10-21; scroll then chip tap hangs the app (product gap) |
| [Guest favorites](./guest-favorites.md) | local only for a guest | proved 2026-10-21, cap included |
| [Question card](./question-card.md) | AI call on open (`suggestQuickAnswers`); writes live to save (`saveQuestionAnswers`) | proved 2026-10-21, save included |
| [Profile and guest upgrade](./profile.md) | reads live; the upgrade writes live (a permanent account) | proved 2026-10-21 |
| [Trio question composer](./trio-composer.md) | AI call (ideas) and writes live (publish); a permanent account only | proved 2026-10-21 |

Order for a full pass: guest onboarding, Home feed, guest favorites, question card, profile, Trio as
guest, then the upgrade of the run's guest to the run's own account (owner's yes; see `../SKILL.md`)
and the account part of profile and Trio.

## Not reachable without a harness

These states need a `-ui-test-*` harness flag or live data that a fresh run does not have. The
skill does not use the flags, so a run reports them as not verifiable:

- the AI daily-limit state (`DAILY_LIMITS` in `functions/aiUsageLimit.js`); the seeded Trio draft;
- a shared question list received from a link (needs a second account that shares one);
- a published Trio question in the app: it stays `pending` and no screen shows it until a moderator
  approves it;
- Best Of rankings: on 2026-10-21 the Today tab showed "No Rankings Yet".
