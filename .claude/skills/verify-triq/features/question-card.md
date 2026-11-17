# Question card

A tap on a question card opens it full screen. The user reads the question, types up to three
answers and saves them, or closes the card. All sub-features proved on 2026-10-21 (run
`2026-10-21-140704-1396`, iOS 27.0, English, as a guest). Re-driven 2026-11-12 (run
`2026-11-12-180550-18bb`, iOS 27.0, English, as a guest): wand, Find Image, Save and Close, relaunch.

**Live-data class:**

- **Opening a card = AI call.** The card shows up to 5 quick answers; when the question has fewer
  than 5 stored ones, it calls the AI callable `suggestQuickAnswers` by itself, with no tap
  (`QuestionCardExpandedView.loadQuickAnswerSuggestions`; seen in the log on 2026-10-21). The
  standing yes for AI calls while the provider is free covers it (`../SKILL.md`).
- **Wand = AI call** (`suggestAIAnswers`); **Find Image = live call** (`suggestAnswerImages`, Pexels
  photos); a saved suggested image calls `saveSuggestedAnswerImage` at save. The server log of the
  2026-11-12 run shows each once with status 200. Standing yes covers them (see `../SKILL.md`).
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
- `quick-answers` chips `question-card-quick-suggestion-<normalizedKey>` (the lower-cased text, for
  example `question-card-quick-suggestion-gentle lighting`) under "Quick Suggestions". Taps on two
  chips on 2026-11-12 reported "screen changed" and left the fields empty: not proved, type the
  answers instead.
- `ai-notice` the line "AI-generated. AI can make mistakes; check important info." (a `sparkles`
  icon and `AIGeneratedNotice.swift`; one identifier per surface): `ai-notice-quick-answers` under the
  chips, `ai-notice-wand-fill` under a field the wand filled. Other surfaces: `ai-notice-trio-ideas`
  and `ai-notice-trio-category` ([Trio](./trio-composer.md)); `ai-notice-query-card`,
  `-query-detail`, `-query-result` have no entry point (AI query screens, previews only).
- `ai-wand` an **empty** answer field has a "Get AI suggestion" button (label; its `wand.and.sparkles`
  is an image id, so `--id` finds nothing, and with three empty fields `--label` finds 3 and axe
  refuses). Tap the first by coordinate (`axe tap -x 292 -y 320 --tap-style physical --udid <UDID>`
  on iPhone 12). A filled field loses its wand. An AI call (`suggestAIAnswers`); the answer takes
  about 5 s and is long.
- `add-image` "Add image" is a `PopUpButton` (a Menu) with two items: "Choose from Library"
  (`photo`, the system picker: not drivable) and "Find Image" (`magnifyingglass`). On an empty field
  Find Image shows "Write an answer first to find matching images."; on a typed answer it shows four
  `Button | Image suggestion by <photographer>` thumbnails and "Photos provided by Pexels". A tap on
  one shows the image on the field: `Change image` (PopUpButton), `Open image`, and an `xmark`
  Button that removes it. The image is saved with the answers (`saveSuggestedAnswerImage`).
- `image-viewer` the answer image viewer. Open: tap the 160x160 `Open image` by coordinate (iPhone 12:
  `axe tap -x 160 -y 440`); `--label` is ambiguous (the remove xmark has the same label). Close: (356,80), id
  `xmark.circle.fill`. `vt ui` under the viewer prints the covered Home tree, and the image has no identifier: read
  the element labelled "Full screen image" with `axe describe-ui --udid U | jq -r '[.. | objects |
  select(.AXLabel=="Full screen image") | .AXFrame] | first // "NONE"'`. Its frame is the zoom and pan readout: 1x
  is `{{0,233.7},{390,390}}`, a double tap gives 2.5x (975), the max is 4x (1560). Judge from the frame, never the
  exit code: `axe` exits 0 whether or not the gesture registered. Reset between runs by closing and reopening.
  AXe 2.0.4 gestures register 10 of 10 (spike 2026-11-18, `~/verify-evidence/triq/2026-11-18-005411-711c`, scripts
  in that folder), with the image centre at (195,428):
  - double tap: `axe tap -x 195 -y 428 --count 2 --tap-style physical --udid U` or
    `axe gesture double-tap -x 195 -y 428 --udid U`;
  - pinch: `axe gesture pinch -x 195 -y 428 --scale 2 --udid U` (2x); `--scale 0.5 --radius 80 --duration 0.6
    --delta 5` zooms out;
  - pan when zoomed: `axe swipe --start-x 290 --start-y 430 --end-x 140 --end-y 430 --duration 0.5 --udid U`; a
    fast flick is the same with `--duration 0.05 --delta 5` and glides a few points further.
  A "should fail" control is one single tap, or two taps 1.5 s apart. Two `axe tap` processes started together
  register as a double tap, so they are no control.
- `card-type` three fields `question-card-input-0`, `-1`, `-2` take answers.
- `card-save` `question-card-fullscreen-save` ("Save answers", an icon-only check mark) saves and
  closes the card at once; the server call runs after the card closes.
- `card-close-clean` `question-card-fullscreen-close` ("Close") with no typed text closes at once.
- `card-close-dirty` Close with unsaved text shows a dialog (`SwiftUI.PlatformAlert`) with two buttons,
  "Save and Close" and "Close Without Saving"; there is no Cancel. "Save and Close" saves like the check
  mark (2026-11-12: Home shows the answers and the image on the card, and a relaunch keeps them).
- Also on the card: `question-card-fullscreen-favorite`, `question-card-fullscreen-list`,
  `question-card-fullscreen-share` (see the other feature files).

## How to get to it (user POV)

- Home → tap any question card (`question-card-<sourceID>-<questionId>`).
- Best Of tab → tap a ranked card (same identifier shape), when there are rankings.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home shows at least one card; the
standing yeses for the AI calls and the save (`../SKILL.md`, Live Firebase).

- `vt ui | grep 'question-card-'` and pick a card id; note its question id. `vt shot home-before-card`.
- `vt tap --id <card id>`. Expect `question-card-fullscreen-root`. `vt shot card-open`, `vt tree card-open`.
- Wand and image (2026-11-12, AI call + live reads): tap the wand of the first empty field by
  coordinate; expect `ai-notice-wand-fill` and a filled `question-card-input-0`. `vt shot wand`. Then
  the "Add image" button of that field (a coordinate tap, x ≈ 335) → `vt tap --once --label 'Find
  Image' --element-type Button` → expect `Image suggestion by …` buttons; tap one by label. `vt shot
  image-picked`. Type two more answers (`vt tap --id question-card-input-1`, `axe type 'milk'`), then
  save with Close → `vt tap --once --label 'Save and Close' --element-type Button`.
- Dirty close: `vt tap --id question-card-input-0`, `axe type 'coffee' --udid <UDID>`, then
  `vt tap --id question-card-fullscreen-close`. Expect the dialog; `vt tap --label 'Close Without
  Saving' --element-type Button`. Expect Home again. Nothing is written.
- Save: reopen the same card, fill `question-card-input-0..2` with real words (read each field's value
  after `axe type`), `vt tap --once --id question-card-fullscreen-save`. Expect Home at once.
- Second view: `vt revive` (ends the app and launches it again), reopen the same card. The three
  fields show the saved answers: after a relaunch they come back from the server, not from the
  closed card.
- Record: `feature=question-card entry=<sourceID> save+dirty-close+relaunch result=pass` and `live=`
  lines for `suggestQuickAnswers`, `suggestAIAnswers`, `suggestAnswerImages`,
  `saveSuggestedAnswerImage` and for `saveQuestionAnswers` with the question id.

## Gotchas

- An empty field's value is its placeholder: "your first answer" / "your second choice" /
  "your final answer".
- The fields capitalise the first letter, and `axe type` can drop a word (see `../SKILL.md`, Gotchas).
- A failed save does not show on the card: the card closes before the server answers. The relaunch
  is the proof.
- An answer image goes through the system photo picker (out of process: never claim it) or Find
  Image (above, driven).
- `vt ui` lists the Home tree under the card cover: read the card's elements after the line
  `Button | Close | question-card-fullscreen-close` (`vt ui | awk '/question-card-fullscreen-close/{f=1} f'`).
