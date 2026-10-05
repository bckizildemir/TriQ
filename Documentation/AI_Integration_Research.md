# AI Integration Research (Updated Context)

## Purpose
This document keeps historical context on provider evaluation. Current production behavior is implemented via provider abstraction in `AIProvider.swift` and runtime config in `AppConfig.swift`.

## Final Direction Used in Code
- Provider abstraction supports `openrouter` and `groq`.
- Default provider currently set to `openrouter` (`TTB/Info.plist`).
- Model is configurable through `AI_MODEL` with provider defaults as fallback.

## Why This Approach Was Chosen
- Avoid vendor lock-in.
- Keep API key and endpoint changes configuration-only.
- Allow fast model experiments without changing app logic.

## Notes
Earlier research favored speed-focused providers. The current architecture preserves that flexibility while keeping the app-level AI interface stable (`AIServiceProtocol`).
