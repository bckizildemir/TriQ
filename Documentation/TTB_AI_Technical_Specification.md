# TTB Technical Specification (Current Baseline)

## Product Goals
- Keep the "three answers" model core across favorites, diary-like entries, and conversation prompts.
- Support guest-first onboarding with optional account upgrade.
- Provide AI-assisted suggestions without breaking the save/share question flow.
- Encourage entries that are memorable, story-friendly, and compatible with image sharing.
- Track meaningful progress via stats + badges.

## Functional Scope
### Authentication
- Email/password sign-in and sign-up.
- Anonymous sign-in.
- Anonymous account linking to permanent account.

### Questions
- Category-based browsing.
- Save/edit answers (3 slots).
- Prompt mix includes favorite-things, ranked preferences, daily moments, memories, and conversation starters.
- Reflection-style prompts are supported where they fit, but prompts should still align with the app's save/share/social use cases.
- Prompt copy should be grammatically correct and should naturally imply multiple answers.
- Prompt copy should favor answers that users may want to revisit, discuss, or pair with images.
- Representative prompts include "What is your Top 3 Harry Potter Movie?" and "Bugun sana iyi gelen seyler nelerdi?".
- Per-user answer storage in `questions/{id}/userAnswers/{uid}`.
- Global question ranking fields (`totalRespondents`, `todayRespondents`, `answerStats`).

### AI
- Query submission with category.
- Exactly 3 responses per query.
- Saved history + usage tracking in user subcollections.
- Configurable provider/model at runtime via app config.

### Badge Progress
- Increment only on first full completion per question.
- Category/total/streak calculations.
- Unlock state and progress stored per user.

## Non-Functional Requirements
- Concurrency safety through actor services.
- UI state mutations on main actor.
- Firestore transaction usage for multi-document consistency.
- Secure API key handling via xcconfig.

## Data Contracts (High-Level)
- `users/{uid}`: profile + stats + badge progress
- `questions/{qid}`: metadata + aggregate respondent stats
- `questions/{qid}/userAnswers/{uid}`: user answer payload
- `users/{uid}/aiQueries/{queryId}`
- `users/{uid}/aiUsage/stats`
- `badges/{badgeId}`
