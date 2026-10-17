# Private Cloud Compute (PCC) for TriQ — Research

Researched 2026-10-15. Status: research only. No code, no entitlement request, no issue yet.

Question: can TriQ use Apple Private Cloud Compute instead of the external AI APIs
(Groq / OpenRouter through Firebase Functions)?

Short answer: yes, but only for part of the user base. PCC is a good primary path on
iOS 27 devices with Apple Intelligence. The Groq/OpenRouter Functions path must stay as
the fallback for every other user.

## TriQ today

- The app calls Firebase callable functions. `functions/aiProviderProxy.js` calls Groq
  (default) or OpenRouter. See `AI_PROVIDER_MIGRATION.md`.
- `functions/aiUsageLimit.js` enforces a server-side usage limit.
- Swift seam: `AIServiceProtocol`; `AIService` is the Functions adapter.
- Deployment target: iOS 18.2.

## What PCC is for third-party apps

- Framework: Foundation Models. Class: `PrivateCloudComputeLanguageModel`
  (iOS / iPadOS / macOS / visionOS / watchOS 27.0+).
- Same API as the on-device model. Swap one line:

  ```swift
  let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel())
  ```

  Tools, instructions and `@Generable` structured output carry over unchanged.
- Model: 32K-token context, reasoning levels `.light` / `.moderate` / `.deep`
  via `ContextOptions(reasoningLevel:)`.
- No API keys, no backend, no auth for these calls.

| Capability    | `SystemLanguageModel` (on-device) | `PrivateCloudComputeLanguageModel` |
| ------------- | --------------------------------- | ---------------------------------- |
| Privacy       | yes                               | yes                                |
| Works offline | yes                               | no                                 |
| Usage limit   | unlimited                         | daily limit per user               |
| Reasoning     | no                                | three levels                       |
| Context       | 4K                                | 32K                                |

## Eligibility and cost

All three are required:

1. Enrolled in the App Store Small Business Program.
2. Fewer than 2 million first-time downloads across **all** of the developer's apps.
3. The managed entitlement `com.apple.developer.private-cloud-compute` assigned to the account.
   Request: <https://developer.apple.com/contact/request/private-cloud-compute/>.

- Cost: no cloud API cost for eligible developers. Apple says expanded access
  "will be available for a fee in the future"; no price published.
- Testing: TestFlight and ad hoc work; test installs do not count as first-time downloads.
- Exit rule: above 2M downloads or out of the Small Business Program → migrate to
  another solution within 6 months.
- Use is subject to the Apple Intelligence Terms and Conditions.

## Limits that matter for TriQ

1. **iOS 27+ only.** Users on iOS 18.2–26 cannot use it. Guard with `#available(iOS 27, *)`.
2. **Apple Intelligence devices and regions only.** Check `model.availability`
   (`.deviceNotEligible`, `.systemNotReady`). The iPhone 12 test simulator/device is not eligible.
   Check `supportedLanguages` / `supportsLocale(_:)` for the prompt languages.
3. **Per-user daily quota, numbers not published.** Read `model.quotaUsage`
   (`isLimitReached`, `.belowLimit(info).isApproachingLimit`, `resetDate`,
   `limitIncreaseSuggestion.show()`). Requests over the limit throw
   `PrivateCloudComputeLanguageModel.Error.quotaLimitReached`. Xcode scheme option
   "Simulated Apple Foundation Models Availability" simulates both quota states.
4. **Client-only.** A Cloud Function cannot call PCC. The prompt logic moves from
   `functions/` into Swift. Server-side work must find a new home:
   `aiUsageLimit.js` (the per-user limit), App Check protection, and any Firestore write
   after the AI reply.
5. **Network required.** Apple advises a retry with the on-device model when the network fails.

Source conflict: Apple's article says users can upgrade iCloud+ to get more quota.
Daring Fireball (2026-06-13) says iCloud+ gives no extra PCC quota in third-party apps
and that larger developers have no paid tier. Test before you rely on the upgrade path.

## Options

| Option | Users covered | Cost | Effort |
| --- | --- | --- | --- |
| A. Groq/OpenRouter only (today) | all | API fees | none |
| **B. Hybrid (recommended):** PCC when available, Functions path otherwise and on quota/network errors | all | lower API fees | medium |
| C. PCC + on-device fallback, no external API | iOS 27 + Apple Intelligence only | free | medium; loses other users |
| D. On-device `SystemLanguageModel` only (iOS 26+) | Apple Intelligence devices | free, offline | low; 4K context may be too small |

### Recommended next steps (option B)

1. Request the PCC entitlement; nothing can be tested before approval.
2. Add a `PrivateCloudComputeAIService` behind `AIServiceProtocol`, selected at runtime
   by availability, with the Functions `AIService` as fallback.
3. Compare quality with the Evaluations framework on TriQ's real prompts
   (question generation, answer suggestions, prompt variations) against the current Groq model.
4. Design quota UI (status label + upgrade button), not a dismissable alert.
5. Decide where the usage limit and post-reply Firestore writes live for PCC calls.

## Sources

- Apple: [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
- Apple: [PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)
- Apple: [Accessing Private Cloud Compute](https://developer.apple.com/private-cloud-compute/)
- Apple: [What's new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Daring Fireball: PCC is severely limited for third-party developers](https://daringfireball.net/linked/2026/06/13/pcc-severely-limited-third-party-developers)
- [State of Surveillance: PCC limits for apps](https://stateofsurveillance.org/news/apple-private-cloud-compute-severely-limited-third-party-developers-2026/)
