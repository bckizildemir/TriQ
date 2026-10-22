# Question card

A tap on a question card opens it full screen. The user reads the question, types up to three
answers and saves them, or closes the card. All sub-features proved on 2026-10-21 (run
`2026-10-21-140704-1396`, iOS 27.0, English, as a guest).

**Live-data class:**

- **Opening a card = AI call.** The card shows up to 5 quick answers; when the question has fewer
  than 5 stored ones, it calls the AI callable `suggestQuickAnswers` by itself, with no tap
  (`QuestionCardExpandedView.loadQuickAnswerSuggestions`; seen in the log on 2026-10-21). Ask the
  owner before a drive that opens a card.
- **Save answers = writes live** (not AI): the callable `saveQuestionAnswers`
  (`functions/questionMutations.js`). It updates `questions/<qid>` (`answerStats`,
  `totalRespondents`, `todayRespondents`, `todayDate`, `lastAnsweredAt`) and sets
  `questions/<qid>/userAnswers/<uid>`. For a permanent account whose save fills all three answers
  for the first time it also merges `users/<uid>` (totals, streak, badges); never for a guest.
  Record the question id.

## Sub-features

- `card-open` a tap on a card opens `question-card-fullscreen-root` (a StaticText with the question as
  its label) as a full-screen cover.
- `guest-banner` a guest sees "Save your answers" with "Dismiss guest warning" and "Create Free
  Account" (the upgrade, writes live).
- `quick-answers` chips `question-card-quick-suggestion-<text>` fill an answer field.
- `ai-wand` each empty field has a "Get AI suggestion" button (identifier `wand.and.sparkles`): an
  AI call (`suggestAIAnswers`). An "Add image" button opens the photo picker or the image callables.
- `card-type` three fields `question-card-input-0`, `-1`, `-2` take answers.
- `card-save` `question-card-fullscreen-save` ("Save answers", an icon-only check mark) saves and
  closes the card at once; the server call runs after the card closes.
- `card-close-clean` `question-card-fullscreen-close` ("Close") with no typed text closes at once.
- `card-close-dirty` Close with unsaved text shows a dialog: "Save and Close" / "Close Without Saving".
- Also on the card: `question-card-fullscreen-favorite`, `question-card-fullscreen-list`,
  `question-card-fullscreen-share` (see the other feature files).

## How to get to it (user POV)

- Home → tap any question card (`question-card-<sourceID>-<questionId>`).
- Best Of tab → tap a ranked card (same identifier shape), when there are rankings.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home shows at least one card; the
owner's yes for the AI call on open and for the save.

- `vt ui | grep 'question-card-'` and pick a card id; note its question id. `vt shot home-before-card`.
- `vt tap --id <card id>`. Expect `question-card-fullscreen-root`. `vt shot card-open`, `vt tree card-open`.
- Dirty close: `vt tap --id question-card-input-0`, `axe type 'coffee' --udid <UDID>`, then
  `vt tap --id question-card-fullscreen-close`. Expect the dialog; `vt tap --label 'Close Without
  Saving' --element-type Button`. Expect Home again. Nothing is written.
- Save: reopen the same card, fill `question-card-input-0..2` with real words (read each field's value
  after `axe type`), `vt tap --once --id question-card-fullscreen-save`. Expect Home at once.
- Second view: `vt revive` (ends the app and launches it again), reopen the same card. The three
  fields show the saved answers: after a relaunch they come back from the server, not from the
  closed card.
- Record: `feature=question-card entry=<sourceID> save+dirty-close+relaunch result=pass` and `live=`
  lines for `suggestQuickAnswers` and for `saveQuestionAnswers` with the question id.

## Gotchas

- An empty field's value is its placeholder: "your first answer" / "your second choice" /
  "your final answer".
- The fields capitalise the first letter, and `axe type` can drop a word (see `../SKILL.md`, Gotchas).
- A failed save does not show on the card: the card closes before the server answers. The relaunch
  is the proof.
- An answer image goes through the system photo picker (out of process) or the image-suggestion
  callables; do not drive them without a separate yes.
