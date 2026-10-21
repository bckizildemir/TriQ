# Trio question composer

The Trio tab lists approved community questions. A permanent account writes a question idea, can
ask the AI for ideas, and submits it for review. A guest gets the account upgrade instead of the
composer. Proved on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0, English): the guest gate as
a guest, the composer as the verify test account.

**Live-data class:** the Trio tab = reads live. **Generate ideas = AI call**: the callable
`generateTrioQuestionSuggestions`. **Submit = writes live**: a client Firestore write of one
`questions/<uuid>` document (`source: userCreated`, `moderationStatus: pending`, `createdBy: <uid>`),
not a callable. Both need the owner's yes per drive. The composer needs a permanent account: the
verify test account (see `../SKILL.md`).

## Sub-features

- `trio-disclosure` the first visit shows a full-screen disclosure "Before You Use Trio"; its
  "Continue" button has no identifier.
- `trio-feed` cards `question-card-trio.feed-<id>`.
- `trio-guest-gate` for a guest, `trio-create-question-button` ("Create Trio question") opens
  `guest-upgrade-sheet`; the composer never opens.
- `trio-open-composer` for an account, the same button opens `trio-create-question-sheet` ("Create
  Trio Question"), with a "Cancel" button (identifier `xmark`).
- `trio-draft` the field `trio-draft-field` ("Question input") takes 8 to 180 characters. Too short
  shows `trio-validation-error` ("Use at least 8 characters.").
- `trio-ideas` `trio-generate-ideas-button` (AI call; needs at least 2 words) shows
  `trio-suggestion-0..2` and `trio-suggested-category` ("AI suggests <category>"). A suggestion tap
  replaces the draft.
- `trio-publish` `trio-publish-button` ("Submit for Review", an icon-only check mark; value `blocked`
  or `ready`) shows `trio-publish-success-toast` ("Submitted for review / Your question will appear
  in Community if it's approved.") for about 0.9 s and closes the sheet, or shows
  `trio-publish-error`.

## How to get to it (user POV)

- Tab bar → Trio → "Continue" on the first visit → the "+" toolbar button.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done.

- `vt tap --label Trio --element-type RadioButton`. First visit: `vt shot trio-disclosure`,
  `vt tap --label Continue --element-type Button`. `vt shot trio-feed`.
- As a guest: `vt tap --id trio-create-question-button`. Expect `guest-upgrade-sheet`, not
  `trio-create-question-sheet`. `vt shot trio-guest-gate`. Close it with "Cancel".
- As the account (sign in or upgrade first, with the owner's yes; [Profile](./profile.md)):
  `vt tap --id trio-create-question-button`. Expect `trio-create-question-sheet` and
  `trio-publish-button` with value `blocked`. `vt shot trio-composer`.
- Tap `trio-draft-field`, type `Abc`: expect `trio-validation-error`. Clear it, type a real
  question of at least 2 words: expect value `ready`.
- Ideas (AI call, owner's yes): `vt tap --once --id trio-generate-ideas-button`. Expect
  `trio-suggestion-0..2`. `vt shot trio-ideas`. `vt tap --id trio-suggestion-0`: the draft changes.
- Submit (writes live, owner's yes): `vt tap --once --id trio-publish-button`, then `vt shot
  trio-published` at once, to catch the toast.
- Record: `feature=trio-composer entry=trio-tab+plus result=pass` and `live=` lines for the AI call
  and for the pending question (its text; the id is not in the log).

## Gotchas

- No screen shows a submitted question: it stays `pending` until a moderator approves it, and the
  Trio feed lists approved questions only. The toast is the only proof in the app; the server
  document needs a Firestore read, which a run does not do.
- On 2026-10-21 the first tap on `trio-create-question-button` as a guest showed no sheet; the
  second did. Read `vt ui` after the first tap before you tap again.
- A guest gets the upgrade form from the "+" button. Its password fields need the "Show password"
  step from `../SKILL.md`.
