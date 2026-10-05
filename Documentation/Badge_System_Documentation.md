# Badge System Documentation

## Overview
Badges are unlocked from actual completed question progress, not simple page visits. Completion means a user fills all 3 answer slots for a question.

## Data Model
### Global Definitions
- Collection: `badges`
- Source of truth fallback: `TTB/Configuration/BadgeDefinitions.json`
- Badge types:
  - `total`
  - `category`
  - `streak`

### User Progress Fields (`users/{uid}`)
- `totalAnswered`
- `dailyAnswers`, `weeklyAnswers`
- `categoryAnswers`
- `completedQuestionIds`
- `currentStreak`, `lastAnsweredDate`
- `unlockedBadges`
- `badgeProgress`

## Runtime Logic
1. User saves answers via `QuestionService.saveAnswers(...)` transaction.
2. Service compares previous vs new answers.
3. Only first full completion of a question increments totals.
4. Badge progress is recalculated in-transaction.
5. `BadgeModel` listens and presents unlock state in UI.

## UI Surfaces
- Profile badge views and detail sheet.
- Badge unlock feedback via `newlyUnlockedBadge` in `BadgeModel`.
- Admin management via `AdminBadgeView` for badge definitions.

## Operational Notes
- Badge definitions can be seeded from JSON to Firestore.
- If `badges` collection is empty, app falls back to bundled JSON.
