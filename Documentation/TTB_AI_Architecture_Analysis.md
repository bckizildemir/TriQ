# TTB Architecture Analysis (Current)

## Product Shape
TTB's product shape is a three-slot capture app: users answer short prompts with exactly three items, save those answers, attach photos when relevant, and share the result. In practice it should behave as a hybrid of favorites app, lightweight diary/notebook, and conversation starter. Prompt design should support not only preferences, but also moments, memories, and shareable experiences.

## Architecture Pattern
The app is SwiftUI + MVVM-style observable models with actor-based services for Firestore/network concurrency boundaries.

## Layering
- Views: `TTB/Views/**`
- State models (`@MainActor`): `QuestionModel`, `AuthModel`, `ProfileModel`, `AIModel`, `BadgeModel`
- Services (`actor` where needed): `QuestionService`, `AIService`, related service types
- Data models: `Question`, `UserAnswer`, `AIQuery`, `AIUsageStats`, `Badge`

## Main Runtime Flow
1. `TTBApp` creates shared models.
2. Auth state determines entry (`LoginView` or `MainTabView`).
3. `QuestionModel`/`ProfileModel` attach listeners and publish view state.
4. User actions call service methods; service updates Firestore.
5. Snapshot listeners and optimistic updates refresh UI.

## Product Navigation (Current)
- Tab 1: Home (category sections + expanded three-slot prompt interaction)
- Tab 2: Most Answered (ranked by daily/all-time respondents)
- Tab 3: AI (query, suggestions, history)

## Backend Topology
- Firestore: users, questions, badges, AI subcollections
- Storage: answer images + profile images
- Firebase Auth: anonymous + email/password + account linking

## Known Risk
`firestore.rules` currently includes a temporary permissive block (`allow read, write: if true;`) and should be tightened for production.
