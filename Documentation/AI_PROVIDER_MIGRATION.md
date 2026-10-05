# AI Provider Migration Notes

## Current Status
Migration to Firebase Callable Functions is complete. The iOS app no longer calls Groq/OpenRouter directly.

## Implemented Changes
- Added callable functions for AI questions, answer suggestions, quick answers, prompt generation, and prompt variations.
- Provider URL/header/request construction and response parsing now run in Functions.
- `AIServiceProtocol` remains stable; `AIService` now calls Firebase Functions.
- `Info.plist` may keep `AI_PROVIDER` and `AI_MODEL` placeholders for compatibility, but real provider keys are not shipped in the app bundle.

## Switching Provider
Set `AI_PROVIDER` for Functions runtime:
- `groq` (current default)
- `openrouter`

Optional model override:
- Set `AI_MODEL`; if omitted, provider default is used.

## Required Secrets
Provider keys are Firebase Functions secrets:
```bash
firebase functions:secrets:set GROQ_API_KEY
firebase functions:secrets:set OPENROUTER_API_KEY
firebase deploy --only functions
```

## Verification
1. Launch app with selected provider.
2. Run one query from AI tab.
3. Confirm successful response and Firestore write.
4. Confirm the built app does not include real Groq/OpenRouter keys.
