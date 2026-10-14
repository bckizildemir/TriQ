# Home feed

Home lists "Today's Questions" and one section per category, each with question cards from the live
database. A pinned chip row above the feed opens a category's full list. Proved on 2026-10-15 (run
`2026-10-15-005622-39fa`, iPhone 12, iOS 26.5, English).

**Live-data class: reads live.** Snapshot listeners on `questions` and `categories`; no write.

## Sub-features

- `today` a "Today's Questions" section with a paged card `question-card-home.today-<questionId>` and
  a page marker `Question 1 of N`.
- `sections` one section per category (for example "Personal", "Self Discovery"), each with a "View All"
  button and cards `question-card-home.category.<CategoryId>-<questionId>`.
- `chips` the chip row `home-category-chip-<CategoryId>` (Personal, SelfDiscovery, Relationships, …;
  24 on 2026-10-15). A chip tap pushes the category list: heading = category name, back button
  `BackButton`, cards `question-card-category.<CategoryId>-<questionId>`.
- `card-buttons` each card has `question-card-share-…`, `question-card-list-…` and
  `question-card-favorite-…` buttons (labels "Share", "Add to question list", "Add to favorites").
- `profile` the toolbar button "Profile" (`person.circle.fill`) opens the profile.
- `tabs` `RadioButton`s "Home" (`lanyardcard.fill`, value `1` when selected), "Best Of"
  (`medal.star.fill`), "Trio" (`sparkles`).

## How to get to it (user POV)

- After [Guest onboarding](./guest-onboarding.md), Home is the first tab.
- From another tab: `vt tap --label Home --element-type RadioButton`.

## Driving it with axe

Preconditions: guest onboarding done; Home on screen.

- `vt ui | grep -E 'question-card-home|home-category-chip|RadioButton'`. Expect at least one
  today card, chips, three tabs. `vt shot home`, `vt tree home`.
- `vt tap --id home-category-chip-Personal`. Expect the heading `Personal`, `BackButton`, and
  `question-card-category.Personal-<id>` cards. `vt shot chip-personal`, `vt tree chip-personal`.
- `vt tap --id BackButton`. Expect `Today's Questions` again.
- Record: `feature=home-feed entry=home-tab+chip-<CategoryId> result=pass`.

## Gotchas

- The chip `Home` (`home-category-chip-Home`) and the tab "Home" share a label; tap the tab with
  `--element-type RadioButton`.
- Chips far right have x beyond 390; axe taps by id still work for those seen on 2026-10-15
  (Personal only was tapped). Scroll the row if a tap by id fails.
- Question text and the number of cards come from live data and change daily. Use ids, not text.
