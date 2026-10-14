# Trio question composer (unproved draft)

On the Trio tab the user writes a question idea, can ask the AI for ideas, and publishes a
community question. Written from source on 2026-10-15; nobody has driven it yet.

**Live-data class:** browsing the Trio tab = reads live. **Generate ideas = paid**: it calls
`generateTrioQuestionSuggestions` (`TTB/Services/AIService.swift`), an App Check-gated AI callable.
**Publish = writes live**: it writes a `questions` document. Both need the owner's yes per drive.

## Sub-features

- `trio-disclosure` the first visit shows a full-screen AI disclosure (`AITabDisclosureView`) that
  the user must dismiss.
- `trio-open-composer` the toolbar button `trio-create-question-button` opens `trio-create-question-sheet`.
- `trio-draft` the field `trio-draft-field` takes the question text.
- `trio-ideas` `trio-generate-ideas-button` (paid) shows `trio-suggestion-<i>` rows.
- `trio-publish` `trio-publish-button` (writes live) shows `trio-publish-success-toast`, or
  `trio-validation-error` / `trio-publish-error`.
- A guest may see `guest-upgrade-sheet` instead of the composer (not verified).

## How to get to it (user POV)

- Tab bar → Trio → dismiss the disclosure on the first visit → the "+" toolbar button.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done.

- `vt tap --label Trio --element-type RadioButton` (element type not yet confirmed; read `vt ui`).
- First visit: `vt shot trio-disclosure`; dismiss it (button not yet identified).
- `vt tap --id trio-create-question-button`. Expect `trio-create-question-sheet`. `vt shot trio-composer`.
- Stop here unless the owner said yes to a paid or publishing drive.

## Gotchas

- **Paid calls succeed in a verify run.** `vt.sh install` gives the app the registered App Check
  debug token (see `../SKILL.md`), so `trio-generate-ideas-button` really calls the paid AI callable.
  Never tap it without the owner's yes for that drive.
- Not yet driven: correct this file after the first drive.
