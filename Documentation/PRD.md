# TTB Product Requirements Document (PRD)

## Product Summary
TTB is an iOS app for capturing, saving, and sharing life in short three-part entries. It should work at the same time as a favorites app, a lightweight diary/notebook, and a conversation starter when people are alone, with friends, or looking for something meaningful to post. The core interaction is a short prompt answered with exactly three responses, but those responses should not feel like dry list fields. Prompts should invite people to share preferences, moments, memories, stories, and photos.

## Product Goals
- Make it easy to capture favorite things, moments, memories, and opinions in a fast, repeatable format.
- Keep entry creation low-friction with a strict 3-answer format.
- Make saved answers feel like a personal notebook users want to revisit.
- Make prompts good conversation starters for solo reflection and social settings.
- Encourage answers that are worth sharing, including photo-supported entries.
- Make progress tangible through totals, streaks, and badge unlocks.
- Offer AI assistance without replacing user-authored answers.

## Target Users
- Users who want to record and revisit favorite things across many categories.
- Users who want a lightweight diary or notebook without long-form writing pressure.
- Users who enjoy prompts about taste, identity, fandoms, friendships, routines, and small life moments.
- Users who want easy conversation starters with friends or on social media.
- Users who benefit from AI suggestions when they feel blocked.

## Core User Journeys
### 1) Onboarding and Access
- User can sign in with email/password.
- User can continue as guest via anonymous auth.
- Guest account can be upgraded/linked to permanent credentials without losing existing data.

### 2) Top 3 Favorites Flow
- User browses category-based prompts on Home.
- User opens an expanded question card and fills exactly 3 answer slots.
- For each slot, user can:
  - Write text manually.
  - Request AI suggestion for that slot.
  - Attach an optional image.
- Save persists per-user answers and image URLs, then updates progress metrics.
- Prompts should cover a mix of:
  - Favorite-things and ranked-preference questions.
  - Diary-like prompts about daily moments, memories, and experiences.
  - Conversation-starting prompts that are easy to answer with friends.
- Prompts should naturally encourage stories, details, and photo-sharing rather than one-word answers.

### 3) Progress and Discovery
- User sees:
  - Category-based question feeds.
  - Most-answered leaderboard (daily and all-time).
  - Comparison view between own answers and top community answers.
- User can favorite questions and revisit favorites.
- User can share question + own answers via iOS share sheet.

### 4) Profile and Achievement
- User can view profile (username, email, profile image).
- User can edit profile fields and upload profile photo.
- User sees daily/weekly/total answer stats.
- User sees badge progress and unlocked badges.
- Admin mode can be toggled from profile (hidden activation flow currently supported in app).

### 5) AI Assistant Tab
- User can ask categorized AI questions from a dedicated AI tab.
- Each AI query returns exactly 3 responses.
- User can:
  - View recent and historical queries.
  - Save/delete query items.
  - Clear history.
  - See daily/weekly/monthly usage counters and limits.
- Query submission is blocked when service is unavailable (missing/invalid API key or usage limits reached).

## Functional Requirements
### Authentication
- Support email/password sign-up and sign-in.
- Support anonymous sign-in.
- Support anonymous-to-email account linking.
- Ensure required user document defaults are present on auth state changes.

### Questions and Answers
- Questions are grouped by categories: `Daily`, `Personal`, `Relationships`, `Career`, `Health`, `Goals`, `Creativity`.
- Prompt response model is fixed to exactly 3 slots per question.
- Content strategy for prompts:
  - Core: favorite-things, ranked lists, preferences, moments, memories, and conversation starters.
  - Optional: reflection prompts in categories where that tone fits.
  - Example prompts:
    - "What is your Top 3 Harry Potter Movie?"
    - "Bugun sana iyi gelen seyler nelerdi?"
    - "Son zamanlarda fotograflarini cekmek istedigin anlar nelerdi?"
  - Writing rules:
    - Each prompt must fit the 3-slot answer model naturally.
    - Avoid singular wording when the user is expected to provide multiple items.
    - Prompts should sound natural, grammatically correct, and easy to answer in spoken Turkish.
    - Prefer prompts that can lead to memories, short stories, shareable moments, or photos.
    - Avoid flat prompts that feel like generic profile forms unless they have a stronger hook.
- Per-user answers are stored under `questions/{questionId}/userAnswers/{uid}`.
- Question-level aggregates are maintained:
  - `totalRespondents`
  - `todayRespondents`
  - `todayDate`
  - `answerStats` (slot-based answer frequencies)
- Save/edit answer flow must preserve aggregate consistency for both first-time answers and edits.

### Images
- Each answer slot supports optional image attachment.
- Question answer images and profile images are uploaded to cloud storage and referenced by URL.
- Existing remote image URLs are loaded for editing and display.

### Favorites and Ranking
- Users can toggle favorite status for a question.
- Favorites list is available and supports reopening questions.
- Most-answered ranking supports:
  - Daily top list.
  - All-time top list.

### AI
- AI provider and model are config-driven (runtime config via app settings/plist keys).
- AI query input includes a category.
- AI output contract is exactly 3 responses.
- Per-user query history and usage stats are persisted.
- Usage enforcement includes daily/weekly/monthly query limits.

### Badges and Stats
- Badge progression is based on first full completion of a question (all 3 slots filled).
- Badge types: total count, category count, streak.
- User progress tracks totals, category counters, streak fields, completed question IDs, unlocked badges, and badge progress percentages.

## Non-Functional Requirements
- Concurrency boundaries:
  - Service layer uses Swift concurrency and `actor` isolation for shared mutable operations.
  - UI-observed model updates occur on `@MainActor`.
- Firestore consistency:
  - Multi-document answer updates and progress calculations are transaction-based.
- Configurability:
  - AI provider/model/API keys are externally configurable without code changes.
- Reliability and UX:
  - Optimistic local state updates are used where appropriate.
  - Error states are surfaced to UI for retry/fallback.

## Product Data Contracts (High Level)
- `users/{uid}`
  - Profile fields, stats (`dailyAnswers`, `weeklyAnswers`, `totalAnswered`), streak fields, badge progress fields, admin/profile metadata.
- `questions/{questionId}`
  - Prompt metadata and aggregate answer/respondent stats.
- `questions/{questionId}/userAnswers/{uid}`
  - User-specific 3-answer payload, answered timestamp, image URLs.
- `users/{uid}/aiQueries/{queryId}`
  - AI question, category, responses, state metadata.
- `users/{uid}/aiUsage/stats`
  - Daily/weekly/monthly/total usage counters and reset metadata.
- `badges/{badgeId}`
  - Badge definitions (with bundled JSON fallback when collection is empty).

## Success Criteria
- Users can complete and save 3-slot entries consistently across favorites, diary-like moments, and conversation prompts.
- Saved answers correctly update stats and badge progress.
- AI assistance works within configured limits and retains useful history.
- Users can discover, favorite, revisit, and share prompts that feel personal, social, and visually expressive.
