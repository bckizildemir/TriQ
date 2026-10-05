# API Key Setup

## Scope
This guide is for developers. End users never enter AI keys manually.

## Files
- Template: `TTB/Secrets.xcconfig.template`
- Local secret file: `TTB/Secrets.xcconfig` (do not commit)
- Firebase Functions secrets for provider API keys

## Setup Steps
1. Copy template:
```bash
cp TTB/Secrets.xcconfig.template TTB/Secrets.xcconfig
```
2. Configure non-secret client defaults only:
```xcconfig
AI_PROVIDER = groq
AI_MODEL =
```
3. Store provider keys in Firebase Functions secrets:
```bash
firebase functions:secrets:set GROQ_API_KEY
firebase functions:secrets:set OPENROUTER_API_KEY
firebase deploy --only functions
```

## Provider Selection
- Runtime provider selection happens in Firebase Functions via `AI_PROVIDER`.
- `AI_PROVIDER=groq` uses the `GROQ_API_KEY` Functions secret and is the default.
- `AI_PROVIDER=openrouter` uses the `OPENROUTER_API_KEY` Functions secret.

## Security Rules
- Never put real Groq/OpenRouter keys in `Secrets.xcconfig`, `Info.plist`, Swift source, or CI build settings for the iOS app.
- Never paste keys into Swift source.
- Use Firebase Functions secrets for production provider credentials.
