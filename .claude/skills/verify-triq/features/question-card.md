# Question card

A tap on a question card opens it full screen. The user reads the question, types up to three
answers and saves them, or closes the card. `card-open` and `card-close-clean` proved on 2026-10-15 (run
`2026-10-15-005622-39fa`). The type, dirty-close and save paths are not yet driven.

**Live-data class:** opening and typing = reads live. **Save answers = writes live**: it calls the
callable `saveQuestionAnswers` (`TTB/Services/QuestionService.swift`), which writes the question
document, an answer-frequency transaction and the user's answer document. Not paid. Ask the owner
before a drive that saves.

## Sub-features

- `card-open` a tap on a Home card opens `question-card-fullscreen-root` as a full-screen cover.
- `card-type` three fields `question-card-input-0`, `-1`, `-2` take answers.
- `card-save` `question-card-fullscreen-save` ("Save answers") saves (writes live).
- `card-close-clean` `question-card-fullscreen-close` ("Close") with no typed text closes at once.
- `card-close-dirty` Close with unsaved text shows a dialog: "Save and close" / "Close without saving".
- Also on the card: `question-card-fullscreen-favorite`, `question-card-fullscreen-list`,
  `question-card-fullscreen-share` (see the other feature files).

## How to get to it (user POV)

- Home → tap any question card (`question-card-<sourceID>-<questionId>`).
- Best Of tab → tap a ranked card (same identifier shape).

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home shows at least one card.

- `vt ui | grep 'question-card-'` and pick the first card id. `vt shot home-before-card`.
- `vt tap --id <card id>`. Expect `question-card-fullscreen-root`. `vt shot card-open`, `vt tree card-open`.
- Read-only path: `vt tap --id question-card-input-0`, `axe type 'coffee' --udid $UDID`, then
  `vt tap --id question-card-fullscreen-close`. Expect the dialog; tap "Close without saving"
  (`vt tap --label 'Close without saving' --element-type Button`). Expect Home again. Nothing is written.
- Save path (owner's yes first): fill the inputs with real words, `vt tap --once --id question-card-fullscreen-save`.
  Prove the save from a second view: reopen the same card and read the inputs' values.

## Gotchas

- Proved ids: `question-card-fullscreen-close` ("Close"), `question-card-fullscreen-save` ("Save answers"),
  `question-card-fullscreen-root` (a StaticText with the question), `question-card-input-0..2`
  (TextFields; their value is the placeholder "your first answer" / "your second choice" /
  "your final answer" while empty), `question-card-fullscreen-share`, `-list`, `-favorite`.
- `card-type`, `card-close-dirty` and `card-save` are not yet driven.
- Typed text goes through autocorrect; use real dictionary words.
- An answer image goes through the system photo picker (out of process) or the image-suggestion
  callables; do not drive them without a separate yes.
