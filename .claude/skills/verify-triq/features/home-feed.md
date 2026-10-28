# Home feed

Home lists "Today's Questions" and one section per category, each with question cards from the live
database. A chip row pinned above the feed opens a category's full list. Proved on 2026-10-15 (run
`2026-10-15-005622-39fa`, iOS 26.5) and on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0,
English), Best Of and the scroll included.

**Live-data class: reads live.** Snapshot listeners on `questions` and `categories`; no write.

## Sub-features

- `today` a "Today's Questions" section (only when today's list is not empty) with a paged card
  `question-card-home.today-<questionId>`. The page dots are a `GenericElement` with the label
  `Question 1 of N`; there is no visible text.
- `sections` one section per category (for example "Personal", "Self Discovery"), each with a "View All"
  button and cards `question-card-home.category.<CategoryId>-<questionId>`.
- `chips` the chip row `home-category-chip-<CategoryId>` (24 chips on 2026-10-21, `Home` among them).
  A chip tap pushes the category list: `Heading` = category name, the back button (identifier
  `BackButton`, label = the previous screen's title, which changes with the time of day), cards
  `question-card-category.<CategoryId>-<questionId>`.
- `scroll` the navigation bar minimizes on scroll down (iOS 27, #101): the greeting
  collapses, the Profile button stays, and the chip row stays pinned where the bar was
  (y = 58 on iPhone 12 after a scroll). Scrolling back up brings the greeting back. A chip
  tap or View All in this state opens the category list; it used to hang the app (#101).
- `card-buttons` each card has `question-card-share-…`, `question-card-list-…` and
  `question-card-favorite-…` buttons (labels "Share", "Add to question list", "Add to favorites";
  the list and favorite labels change when the question is already saved).
- `profile` the toolbar button "Profile" (identifier `person.circle.fill`) opens
  [Profile](./profile.md) as a full-screen cover. For an account with a photo the button shows the photo.
- `tabs` `RadioButton`s "Home" (`lanyardcard.fill`, value `1` when selected), "Best Of"
  (`medal.star.fill`), "Trio" (`sparkles`). Each tab keeps its pushed screen.
- `best-of` the Best Of tab: `Heading` "Most Answered", `RadioButton`s "Today" (value `1`) and
  "All Time", ranked cards when there are answers. On 2026-10-21 it showed the empty state
  "No Rankings Yet" with a button back to today's questions.

## How to get to it (user POV)

- After [Guest onboarding](./guest-onboarding.md), Home is the first tab.
- From another tab: `vt tap --label Home --element-type RadioButton`.

## Driving it with axe

Preconditions: guest onboarding done; Home on screen, scrolled to the top.

- `vt ui | grep -E 'question-card-home|home-category-chip|RadioButton|Profile'`. Expect at least one
  card, chips, three tabs, the Profile button. `vt shot home`, `vt tree home`.
- `vt tap --id home-category-chip-Personal` **before** any scroll (see Gotchas). Expect the heading
  `Personal`, `BackButton`, and `question-card-category.Personal-<id>` cards. `vt shot chip-personal`,
  `vt tree chip-personal`.
- `vt tap --id BackButton`. Expect the Home feed and the chip row again.
- Scroll: `axe swipe --start-x 195 --start-y 600 --end-x 195 --end-y 250 --udid <UDID>`. Expect the
  bar minimized (no greeting heading), the Profile button, and the chip row pinned at the top.
  `vt shot home-scrolled`. A chip tap in this state opens the category list, and so does View All.
- `vt tap --label 'Best Of' --element-type RadioButton`. Expect `Most Answered`. `vt shot best-of`.
  Back with `vt tap --label Home --element-type RadioButton`.
- Record: `feature=home-feed entry=home-tab+chip-<CategoryId> result=pass`.

## Gotchas

- **Fixed (#101, 2026-10-28):** a chip tap or View All after a scroll hung the app (100 % CPU, a
  layout loop) while Home minimized the navigation bar on iOS 27. The cause was the *destination*:
  `CategoryQuestionsView` asked for a large title, and expanding a large title out of the minimized
  bar never settles during the push transition. It now uses an inline title. Never push a
  large-title screen from a root that minimizes its bar (see `Backport+ToolbarMinimization.swift`).
  If the hang returns, `vt doctor` fails with "the app is hung" and `vt revive` recovers.
- The chip `Home` (`home-category-chip-Home`) and the tab "Home" share a label; tap the tab with
  `--element-type RadioButton`.
- Chips far right have x beyond 390; axe taps by id still work for those seen. Scroll the row if a
  tap by id fails.
- Question text and the number of cards come from live data and change daily. Use ids, not text.
