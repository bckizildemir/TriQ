# Guest favorites

A guest taps the star on a question card to keep it. For a guest the favorites live only on the
device (`GuestFavoriteModel`, UserDefaults key `guest.favorite.questionIds`), at most 10. All
sub-features proved on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0, English). Re-driven
2026-11-12 (run `2026-11-12-180550-18bb`): toggle, milestone toast, strip, the strip CTA into the
upgrade and the migration toast, and the signed-in star. The cap (`fav-cap`) was not re-driven.

**Live-data class:** local only for a guest (no `toggleQuestionFavorite` / `addQuestionFavorites`
in the device log). For a signed-in account the same tap calls the callable
`toggleQuestionFavorite` (writes live); this file covers the guest only.

## Sub-features

- `fav-toggle` the star (`star` → `star.fill`) `question-card-favorite-<sourceID>-<questionId>`; its
  label goes from "Add to favorites" to "Remove from favorites".
- `fav-fullscreen` the star `question-card-fullscreen-favorite` inside an open card does the same.
- `fav-milestone` the 3rd favorite shows the toast `guest-favorite-milestone-toast` ("3 favorites
  saved" / "On this device only · guests keep up to 10"), once per app session.
- `fav-strip` Profile → "My Favorites" shows `guest-favorite-strip` ("3 of 10 favorites · saved on
  this device") with `guest-favorite-strip-cta` ("Keep them") above the favorite cards. Home never
  shows the strip.
- `fav-migrate` "Keep them" (`guest-favorite-strip-cta`) opens `guest-upgrade-sheet`. After the
  upgrade, Home shows the toast `guest-favorite-migration-toast` ("Your favorites have been saved.")
  for a few seconds, the server log shows `addquestionfavorites` 200 once, and My Favorites lists the
  same cards with no strip.
- `fav-account` as an account, the same star calls the callable `toggleQuestionFavorite` (log: 200); the
  label flips to "Remove from favorites" and Profile → My Favorites lists the card as
  `question-card-favorites-<questionId>`.
- `fav-cap` the 10th favorite is saved and opens `favorite-limit-sheet` ("You've reached 10
  favorites!", `favorite-limit-create-account` "Create Free Account", `favorite-limit-maybe-later`
  "Maybe Later"). An 11th star opens the sheet again and is not saved.

## How to get to it (user POV)

- Home or a category list → the star on any card.
- Open a card → the star in the card.
- Home → Profile → My Favorites for the list and the strip.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home shows a card, scrolled to the top.

- `vt tap --id home-category-chip-Personal`, then `vt ui | grep 'question-card-favorite-'`; pick ids
  with a frame above y = 735 (the tab bar covers the rest).
- Tap three stars on three questions. The same id now reads "Remove from favorites". After the 3rd,
  `vt shot fav-milestone` **at once**: the toast goes away before a `vt ui` read.
- Strip: `vt tap --id BackButton`, `vt tap --label Profile`, tap the "My Favorites" row. Expect
  `guest-favorite-strip` and three cards. `vt shot fav-strip`, `vt tree fav-strip`.
- Full screen: open one card there, `vt tap --id question-card-fullscreen-favorite` (label goes to
  "Add to favorites"), close the card. The list now has one card less.
- Cap: favorite more questions from several chips until the count is 10. Expect
  `favorite-limit-sheet`. `vt shot fav-cap`, `vt tap --id favorite-limit-maybe-later`. One more star:
  the sheet opens again and that star stays "Add to favorites". On 2026-10-21 this took about 22
  taps and 10 minutes, because a list swipe moves about 300 points.
- Local only: the device log shows no `toggleQuestionFavorite` / `addQuestionFavorites` call.
- Upgrade by the strip: with the strip on screen, `vt tap --id guest-favorite-strip-cta` (on
  2026-11-12 the first tap showed no sheet and the second opened it: read `vt ui` for
  `guest-upgrade-sheet` before you tap again), then fill the form as in [Profile](./profile.md). The
  upgrade **writes live** (standing yes). Take `vt shot` right after "Create Account": the toast
  goes away within seconds.
- Signed-in star (writes live): `vt tap --once --id question-card-favorite-home.today-<questionId>`.
  Expect "Remove from favorites" on that id, then Profile → `profile-content-favorites` lists it.
- Record: `feature=guest-favorites entry=category-list-star+profile-favorites+cap result=pass`.

## Gotchas

- `favorite-limit-create-account` and the strip's `guest-favorite-strip-cta` open the account upgrade,
  which writes live (covered by the standing yes until release; see
  [Profile and guest upgrade](./profile.md)).
- A guest's favorites stay on the device only; a fresh device starts with none. On 2026-11-12 the
  upgrade carried the 3 favorites over: `addquestionfavorites` 200 in the server log (on 2026-10-21 the
  device log showed no such call; the server log is the proof).
