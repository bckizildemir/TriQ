# TTB AI API Reference

## Configuration Keys
Runtime AI configuration is owned by Firebase Functions:
- `AI_PROVIDER` (`openrouter` | `groq`)
- `AI_MODEL` (optional override)
- `OPENROUTER_API_KEY` Functions secret
- `GROQ_API_KEY` Functions secret

The iOS app must not ship real Groq/OpenRouter keys.

## Core Types
### `AICategory`
- Enum used for categorizing AI queries.
- Provides localized title, icon, description, and keyword-based fallback categorization.

### `AIQuery`
- Fields: `id`, `question`, `responses`, `timestamp`, `category`, `isSaved`, `isLoading`, `error`.
- Firestore mapping: `toFirestore()` / `fromFirestore(...)`.

### `AIUsageStats`
- Fields: `dailyQueries`, `weeklyQueries`, `monthlyQueries`, `totalQueries`, `lastQueryDate`, `favoriteCategory`, `lastResetDate`.
- Effective limits (currently enforced by model): daily 20, weekly 100, monthly 300.

## Service Contracts
### `AIServiceProtocol`
- `askQuestion(_:category:) async throws -> [String]`
- `suggestAnswers(for:) async throws -> [String]`
- `suggestQuickAnswers(for:category:excluding:limit:) async throws -> [String]`
- `generateQuestionPrompt(from:category:) async throws -> String`
- `generateQuestionVariations(from:count:) async throws -> [String]`
- `generateTrioQuestionSuggestions(from:count:excluding:availableCategoryIDs:) async throws -> TrioQuestionSuggestionResult`

### `AIService`
- Actor-based for safe concurrency.
- Calls Firebase Callable Functions in `europe-west1`.
- Maps callable/provider failures to `AIServiceError`.
- Enforces exactly 3 responses for 3-answer flows.

### Trio question composer (`TrioPromptModel` / `TrioPromptComposerView`)
- Question suggestions (`generateTrioQuestionSuggestions`) are requested after the user types at least 2 words and pauses briefly; the user can also request more suggestions manually.
- Each suggestion response returns exactly 3 full Trio question candidates plus one suggested app category ID from the provided available category IDs.
- The composer keeps manual question authoring and manual category choice available; a user-selected category is not silently overwritten by later AI suggestions.
- Callable `generateQuestionVariations` parses provider text with a strict pass (numbered lines / JSON / markdown, each ending in `?`), then a lenient pass that can append a missing `?`, skips obvious preamble lines, enforces a minimum length, and de-duplicates case-insensitively before returning exactly `count` items.
- Callable `generateTrioQuestionSuggestions` uses the same question normalization behavior, accepts previously shown suggestions in `excluding`, and returns `{ suggestions, suggestedCategoryId }`.
- On failure, the callable may return `FunctionsErrorCode.dataLoss` with `details.reason` set to `insufficient-responses` (includes `count`), `invalid-response`, `empty-response`, or `parsing`. The iOS `AIService` maps these to `insufficientResponses`, `invalidResponse`, or `parsingError` for clearer UI copy.

### `AIUsageService` (inside `AIModel.swift`)
- Reads/writes stats at `users/{uid}/aiUsage/stats`.
- Supports `getUsageStats`, `updateUsageStats`, `canMakeQuery`, `incrementQueryCount`.

## Firestore Paths
- `users/{uid}/aiQueries/{queryId}`
- `users/{uid}/aiUsage/stats`

## Error Surface
Primary user-visible errors:
- Missing key (`noAPIKey`)
- Invalid key (`apiKeyInvalid`)
- Rate limit (`rateLimitExceeded`)
- Timeout (`timeout`)
- Parsing/format errors (`parsingError`, `insufficientResponses`)
