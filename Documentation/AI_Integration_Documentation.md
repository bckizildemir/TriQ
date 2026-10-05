# TTB AI Integration Documentation

## Overview
TTB includes an AI tab that returns exactly 3 responses per query, aligned with the app's three-slot interaction model. The broader product is not limited to top-three favorites; it also acts as a lightweight diary/notebook and a conversation-starter app. The AI layer should therefore help users brainstorm entries for favorite-things questions, daily moments, memories, and prompts that may lead to photo-backed answers. iOS uses `AIModel` + `AIService`, while provider calls run through Firebase Callable Functions. Per-user history and usage tracking remain in Firestore.

## Current Product State
- Main tabs: `Home`, `Most Answered`, `AI`.
- AI provider: configurable (`groq` default, `openrouter` supported).
- Prompt/response language: Turkish-first prompts with structured numbered outputs.
- Query persistence: `users/{uid}/aiQueries`.
- Usage stats: `users/{uid}/aiUsage/stats`.

## Core Flow
1. User submits a question in `AIQueryInputView`.
2. `AIModel` validates text length and usage eligibility.
3. `AIService` calls Firebase Callable Functions.
4. Functions validate auth, build the provider request, call Groq/OpenRouter, and normalize responses.
5. `AIService` maps callable errors to `AIServiceError` and enforces exactly 3 items for 3-answer flows.
6. `AIModel` updates usage counters and optional saved history.

## Integration Components
- `TTB/Views/AI/*`: AI UI screens and cards.
- `TTB/Models/AIModel.swift`: orchestration, state, Firestore sync.
- `TTB/Services/AIService.swift`: callable transport, local rate limiting, error mapping.
- `functions/aiProviderProxy.js`: provider request building, parsing, and provider error mapping.
- `TTB/Utilities/AppConfig.swift`: non-secret app configuration and usage limits.

## Runtime Safeguards
- Per-minute local request guard in `AIService`.
- Daily/weekly/monthly user limits from `AIUsageStats`.
- Explicit typed errors (`AIServiceError`) for UI-level messaging.
- Provider key validation happens in Firebase Functions through configured secrets.
