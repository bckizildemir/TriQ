# Guest favorites

A guest taps the heart on a question card to keep it. For a guest the favorites live only on the
device (`GuestFavoriteModel`, UserDefaults). `fav-toggle` proved on 2026-10-15 (run `2026-10-15-005622-39fa`) from a category list, with Home as the second view. The other sub-features are not yet driven.

**Live-data class:** local only for a guest. For a signed-in account the same tap calls the callable
`toggleQuestionFavorite` (writes live); this file covers the guest only.

## Sub-features

- `fav-toggle` the heart `question-card-favorite-<sourceID>-<questionId>` on a Home card toggles the favorite.
- `fav-fullscreen` the heart `question-card-fullscreen-favorite` inside an open card does the same.
- `fav-strip` after a favorite, Home can show `guest-favorite-strip` with `guest-favorite-strip-cta`.
- `fav-milestone` a milestone toast `guest-favorite-milestone-toast` can show.
- `fav-cap` the 10th favorite opens `favorite-limit-sheet` (needs 10 real favorites; slow).

## How to get to it (user POV)

- Home → the heart on any card.
- Home → open a card → the heart in the card.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home shows a card.

- `vt tap --id home-category-chip-Personal`, then `vt ui | grep 'question-card-favorite-'`; pick one
  id, for example `question-card-favorite-category.Personal-<questionId>`.
- `vt tap --id <heart id>`. The same id now has the label "Remove from favorites" (was "Add to
  favorites"). `vt shot fav-after-tap`, `vt tree fav-after-tap`.
- Second view: `vt tap --id BackButton`. On Home, `question-card-favorite-home.category.Personal-<questionId>`
  (same question id) reads "Remove from favorites". `vt shot home-after-fav`, `vt tree home-after-fav`.
- Local only: the device log shows no `toggleQuestionFavorite` / `addQuestionFavorites` call.
- Record: `feature=guest-favorites entry=category-list-heart second-view=home result=pass`.

## Gotchas

- `fav-fullscreen`, `fav-strip`, `fav-milestone` and `fav-cap` are not yet driven (the strip did not show after one favorite).
- A guest's favorites stay on the device only; a fresh device starts with none.
