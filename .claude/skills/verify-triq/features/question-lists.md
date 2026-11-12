# Question lists

Profile → "Question Lists" holds an account's own lists of questions. A guest sees an "Account
Required" note instead. An account creates a list, adds questions, renames it, deletes it and can
open a share sheet for it. Proved on 2026-11-12 (run `2026-11-12-180550-18bb`, iOS 27.0, English,
as the run's own account) except receiving a shared list.

**Live-data class: writes live.** The callables `createQuestionList`, `setQuestionInList`,
`updateQuestionList`, `deleteQuestionList` (server log 2026-11-12: each 200 once). Covered by the
standing yes for live writes (`../SKILL.md`). Record each list in a `live=` line. The share sheet
creates a share link only when its toolbar share button is tapped; the recipe does not tap it.

## Sub-features

- `lists-guest` as a guest: `Heading` "Question Lists", "Account Required", "Create an account to save
  question lists and share them later." No Create button.
- `lists-empty` as an account: two `RadioButton`s "Lists" (value `1`) and "Shared", the text "No
  Question Lists" ("Create a new list for sharing with your beloved ones.") and a bottom bar Button
  "Create" (identifier `plus`).
- `list-create` "Create" opens the sheet "New List": a focused field "List name", "Cancel" (`xmark`)
  and "Create" (`checkmark`, grey until there is text). Save → the row
  `question-list-row-<listId>` with the label "<name>, 0 questions".
- `list-detail` a tap on the row opens the list: `Heading` = name, `question-list-detail-share-button`
  ("Share List", `[disabled]` while the list is empty), `question-list-detail-add-button` ("Add
  Questions"), and for an empty list the text "Add questions to build a list you can share later." with
  an "Add Questions" button.
- `list-add` "Add Questions" opens `question-list-picker-sheet`: category chips (All, Books, …), rows
  "<question>, <category>" with a `+` at the right, a search field. A tap on a `+` turns it into
  `checkmark.circle.fill` ("Selected"); the check mark at the top right confirms. The list detail then
  shows `question-card-questionList.<listId>-<questionId>` (a card with share, a filled list
  button and favorite buttons) and the Share List button is enabled.
- `list-rename` a swipe left on the row shows "Edit" (`pencil`) and "Delete" (`trash`). "Edit" opens
  "Edit List" with the name; Save is the same `checkmark` button.
- `list-delete` "Delete" opens a `Sheet` "Delete List?" with "Cancel" and "Delete". After "Delete" the row
  is gone and "No Question Lists" is back.
- `list-share-sheet` the detail's Share List button opens a bottom sheet "Share List":
  `question-list-share-dismiss-button` ("Cancel", `xmark`), `question-list-share-toolbar-share-button`
  (the system share), a toggle "Include my text answers" (on by default) and the text "One link can be
  accepted by up to 25 permanent-account recipients. Empty lists can be shared and filled in later."
- `list-from-card` on a Home card, "Add to question list" (`question-card-list-…`) opens a "Question
  Lists" sheet with "Done" and "Create" (empty account) or the lists to tick; a guest gets
  `guest-upgrade-sheet`.
- `list-receive` **verified-unreachable**: receiving a shared list (the "Shared" tab, the link
  `questionSharePage`, `sendQuestionListShareReply`, `markQuestionListShareReplySeen`) needs a second
  permanent account that opens a link made by the first. Route tried: Profile → Question Lists → a list's
  share sheet, up to (not including) the toolbar share button. The "Shared" tab was not opened. A run has one account and one device, so nothing receives the link.
  Prerequisite: a second permanent account (a yes for it) and a way to open the first account's link
  on it.

## How to get to it (user POV)

- Home → "Profile" toolbar button → "Question Lists" row (a Button, the third row of "My Content").
- Home or a category list → a card's bookmark button → the same lists in a sheet.

## Driving it with axe

Preconditions: the run's own account exists (upgrade done, [Profile](./profile.md)); Home on screen.
Guest first: Profile → `vt tap --label 'Question Lists' --element-type Button` → expect "Account
Required". `vt shot question-lists-guest`.

As the account:

- `vt tap --label Profile --element-type Button`, `vt tap --label 'Question Lists' --element-type
  Button`. Expect "No Question Lists". `vt shot lists-empty`.
- `vt tap --label Create --element-type Button`. The name field is already focused: `axe type 'Movies'
  --udid <UDID>`. `vt tap --once --id checkmark`. Expect `question-list-row-<id>` "Movies, 0
  questions" (read the id from `vt ui | grep question-list-row`). `vt shot list-created`.
- `vt tap --id question-list-row-<id>` → expect `Heading | Movies`. `vt tap --id
  question-list-detail-add-button` → expect `question-list-picker-sheet`. Tap the first `+`
  by coordinate (`axe tap -x 362 -y 216 --tap-style physical --udid <UDID>`), then the check mark by
  coordinate (x 351, y 85). Expect `question-card-questionList.<id>-<qid>` and the Share List
  button enabled. `vt shot list-with-question`.
- Share sheet: `vt tap --once --id question-list-detail-share-button` → expect
  `question-list-share-dismiss-button`; `vt shot list-share`; `vt tap --id
  question-list-share-dismiss-button`. Do not tap the toolbar share button.
- Rename: `vt tap --id BackButton`, swipe the row left (`axe swipe --start-x 330 --start-y 232
  --end-x 100 --end-y 232 --udid <UDID>`), `vt tap --label Edit --element-type Button`. Clear the name
  with `axe key-sequence --keycodes 42,42,42,42,42,42,42,42 --udid <UDID>` (Backspace), type `Books`, then
  save with the coordinate tap (x 351, y 85). Expect the row "Books, 1 questions" with the same id.
- Delete: swipe the row left again, `vt tap --label Delete --element-type Button` → the `Sheet` "Delete
  List?" → `vt tap --once --label Delete --element-type Button`. Expect "No Question Lists".
  `vt shot list-deleted`.
- Server check (read-only): the count query in `../SKILL.md` ("After a deploy or a merge", step 3)
  shows `createquestionlist`, `setquestioninlist`, `updatequestionlist`, `deletequestionlist` with 200.
- Record: `feature=question-lists entry=profile-question-lists create+add+rename+delete result=pass` and a
  `live=` line for the list (name, id).

## Gotchas

- `axe key 42` did nothing; `axe key-sequence --keycodes 42,…` deleted text.
- `vt tap --once --id checkmark` and `vt tap --label Create` can hit a different button: the "New List"
  and "Edit List" sheets share identifiers with the sheet behind them. After the tap, read `vt ui` for
  `question-list-row-<id>`; on the rename on 2026-11-12 the first tap with the keyboard up only closed the
  keyboard and a second tap at (351, 85) saved.
- `vt ui` also prints the Home tree behind the sheet; look at the lines for the sheet (`awk` from its
  identifier) or take a `vt shot`.
- The row's swipe actions are not in the tree until the swipe is done.
