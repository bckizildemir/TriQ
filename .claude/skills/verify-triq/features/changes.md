# Change map: what to drive after a deploy or a merge

The check loop (`../SKILL.md`, "After a deploy or a merge") reads this file to pick the journeys a
change touches. Find each changed path or function below; drive the union of the journeys, as each
account kind listed. Built from source on 2026-11-12 (#138); `functions/index.js` exports 31
functions, all callables except `questionSharePage` (HTTP). No Firestore triggers, no scheduled
functions.

## Server functions (`functions/`)

| Changed function | Journey (feature file) | Account kinds |
| --- | --- | --- |
| `claimUsername`, `releaseUsername` | guest upgrade ([profile](./profile.md)) | guest → account |
| `resolveUsername` | sign in with a username: **no feature file** | account |
| `deleteOwnAccountData`, `purgeOwnAnswersForAccountDeletion` | Delete Account ([profile](./profile.md)) | guest and account |
| `saveQuestionAnswers` | save answers ([question card](./question-card.md)) | guest and account |
| `suggestQuickAnswers`, `suggestAIAnswers` (AI) | open a card, wand ([question card](./question-card.md)) | guest |
| `suggestAnswerImages`, `saveSuggestedAnswerImage` | "Add image" on a card ([question card](./question-card.md)); the pick has **no feature file** | account |
| `generateQuestionPrompt`, `generateQuestionVariations`, `generateTrioQuestionSuggestions` (AI) | ideas ([Trio composer](./trio-composer.md)) | account |
| `toggleQuestionFavorite` | favorite as an account ([home feed](./home-feed.md), [question card](./question-card.md)) | account |
| `addQuestionFavorites` | guest favorites carried over by the upgrade ([guest favorites](./guest-favorites.md), [profile](./profile.md)) | guest → account |
| `createQuestionList`, `updateQuestionList`, `deleteQuestionList`, `setQuestionInList` | Profile → Question Lists: **no feature file** | account |
| `*QuestionListShare*`, `sendQuestionListShareReply`, `markQuestionListShareReplySeen`, `questionSharePage` | share a list: **no feature file** (needs a second account) | account × 2 |
| `askAIQuestion` (AI) | no entry point outside previews (2026-11-12): nothing to drive; say so | — |
| `publishPendingContentRelease`, `sendTestContentReleaseNotification` | admin only: not drivable; say so | — |

A shared module (`functions/aiProviderProxy.js`, `aiUsageLimit.js`, `package.json`,
`package-lock.json`) touches every function that uses it. For a dependency bump, drive one journey
per kind of call: guest onboarding + upgrade (`claimUsername`), a card open and a save
(`suggestQuickAnswers`, `saveQuestionAnswers`), Trio ideas (`generate*`), Delete Account as the
account (last; the guest delete only when `deleteOwnAccountData` itself changed). Proved this way on
2026-11-12 (run `2026-11-12-004718-1aa9`).

## Rules and app code

| Changed path | Journey |
| --- | --- |
| `firestore.rules` `users`, `usernames` | guest onboarding, profile (upgrade, edit, delete) |
| `firestore.rules` `questions`, `userAnswers` | home feed, question card (save) |
| `firestore.rules` `aiUsage*`, `aiConfig`, `users/*/aiQueries` | question card (open), Trio ideas |
| `firestore.rules` `questionLists`, `questionListShares` | question lists, list share (no feature files) |
| `storage.rules` `answers/` | question card "Add image"; Delete Account |
| `storage.rules` `profiles/` | profile photo (the picker runs out of process: not drivable) |
| `TTB/Views/...` or `TTB/Models/...` | the feature file whose sub-features name that screen; when unsure, grep the view name in `features/` |

A journey with **no feature file**: drive it anyway from the screens, then add the feature file in
the same PR as the run's notes, or record the gap in `STATUS.md` (global rule, "Verify it yourself").
