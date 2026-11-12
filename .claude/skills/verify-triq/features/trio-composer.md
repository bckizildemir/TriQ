# Trio question composer

The Trio tab lists approved community questions. A permanent account writes a question idea, can
ask the AI for ideas, and submits it for review. A guest gets the account upgrade instead of the
composer. Proved on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0, English): the guest gate as
a guest, the composer as the run's own account. Re-driven 2026-11-12 (run `2026-11-12-180550-18bb`,
iOS 27.0, English): guest gate, validation, ideas, submit.

**Live-data class:** the Trio tab = reads live. **Generate ideas = AI call**: the callable
`generateTrioQuestionSuggestions`. **Submit = writes live**: a client Firestore write of one
`questions/<uuid>` document (`source: userCreated`, `moderationStatus: pending`, `createdBy: <uid>`),
not a callable. Both are covered by the standing yeses in `../SKILL.md` (AI calls while the provider is free; live writes until release). The composer needs a permanent account: the
run's own account (see `../SKILL.md`, "A run's own account").

## Sub-features

- `trio-disclosure` the first visit shows a full-screen disclosure "Before You Use Trio"; its
  "Continue" button has no identifier. `vt ui` prints the Trio feed under it (title `Heading | Trio`):
  take a `vt shot` to see the cover.
- `trio-feed` cards `question-card-trio.feed-<UUID>` with share, list and favorite buttons and an
  "Added by @<username>" pill. The feed was not empty on 2026-11-12, so the empty-feed state was not
  seen.
- `trio-guest-gate` for a guest, `trio-create-question-button` ("Create Trio question") opens
  `guest-upgrade-sheet`; the composer never opens.
- `trio-open-composer` for an account, the same button opens `trio-create-question-sheet` ("Create
  Trio Question"), with a "Cancel" button (identifier `xmark`).
- `trio-draft` the field `trio-draft-field` ("Question input", placeholder "e.g. LOTR characters,
  comfort foods, dream travel spots...") takes 8 to 180 characters; a counter shows "72/180" once
  there is text. Too short shows `trio-validation-error` ("Use at least 8 characters."), too long
  ("tooLong", 200 characters tried) shows the same id with "Keep it under 180 characters."; the
  publish button stays `blocked` and `[disabled]` in both. The source says `trio-draft-field` is also
  used in `QuestionPreviewCard`: not seen on screen.
- `trio-ideas` `trio-generate-ideas-button` (AI call; label "Generate question ideas"; `[disabled]`
  with an empty or one-word draft, enabled from 2 words and for a too-long draft) shows
  `trio-suggestion-0..2`, the line `ai-notice-trio-ideas`, `trio-suggested-category` ("AI suggests
  Food") with `ai-notice-trio-category`, and the same button now labelled "Generate more". The source
  disables it at the daily AI limit and while a call runs: not reachable (limit) or too short to
  catch (running). A suggestion tap replaces the draft and shows a check mark on it; the Category
  chips have no identifier (not captured).
- `trio-publish` `trio-publish-button` ("Submit for Review", an icon-only check mark; value `blocked`
  or `ready`) shows `trio-publish-success-toast` ("Submitted for review / Your question will appear
  in Community if it's approved.") for about 0.9 s and closes the sheet, or shows
  `trio-publish-error` (not reproduced).

## How to get to it (user POV)

- Tab bar → Trio → "Continue" on the first visit → the "+" toolbar button.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done.

- `vt tap --label Trio --element-type RadioButton`. First visit: `vt shot trio-disclosure`,
  `vt tap --label Continue --element-type Button`. `vt shot trio-feed`.
- As a guest: `vt tap --id trio-create-question-button`. Expect `guest-upgrade-sheet`, not
  `trio-create-question-sheet`. `vt shot trio-guest-gate`. Close it with "Cancel".
- As the account (upgrade the run's guest first, standing yes; [Profile](./profile.md)):
  `vt tap --id trio-create-question-button`. Expect `trio-create-question-sheet` and
  `trio-publish-button` with value `blocked`. `vt shot trio-composer`.
- Tap `trio-draft-field`, type `Abc`: expect `trio-validation-error` and an ideas button `[disabled]`.
  Optional: type `milk ` 40 times (`axe type "$(printf 'milk %.0s' $(seq 1 40))"`): expect "Keep it
  under 180 characters.". Clear it with Backspace: `axe key-sequence --keycodes 42,42,…` (100 codes a
  call, `--delay 0.01`; `axe key 42` did nothing), then type a topic of 2 words (`coffee shops`):
  expect value `ready` and no validation line.
- Ideas (AI call, standing yes): `vt tap --once --id trio-generate-ideas-button`. Expect
  `trio-suggestion-0..2`. `vt shot trio-ideas`. `vt tap --id trio-suggestion-0`: the draft changes to that suggestion.
- Submit (writes live, standing yes): `vt tap --once --id trio-publish-button`, then `vt shot
  trio-published` at once, to catch the toast.
- Record: `feature=trio-composer entry=trio-tab+plus result=pass` and `live=` lines for the AI call
  and for the pending question (its text; the id is not in the log).

## Gotchas

- On 2026-11-12 the sheet closed on submit and the toast was already gone in the `vt shot` taken
  after the tap command returned: the closed sheet and the Trio feed are the proof.
- No screen shows a submitted question: it stays `pending` until a moderator approves it, and the
  Trio feed lists approved questions only. The toast is the only proof in the app; the server
  document needs a Firestore read, which a run does not do.
- On 2026-10-21 the first tap on `trio-create-question-button` as a guest showed no sheet; the
  second did. Read `vt ui` after the first tap before you tap again.
- A guest gets the upgrade form from the "+" button. Its password fields need the "Show password"
  step from `../SKILL.md`.
