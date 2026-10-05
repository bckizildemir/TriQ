---
name: ttb-share-link-deep-links
description: Use when implementing, reviewing, or debugging TTB question or question-list sharing, Firebase Hosting share pages, canonical web URLs, Apple associated domains, AASA files, custom URL schemes, Universal Links, or in-app deep-link routing.
metadata:
  short-description: Maintain TTB share links and deep links
---

# TTB Share Links and Deep Links

Use this for TTB work involving `https://ttbp-9d652.web.app/q/...`, `https://ttbp-9d652.web.app/l/...`, `ttbp://...`, Firebase Hosting rewrites, share previews, accepted list links, or iOS deep-link routing.

## Core Map

- URL models/routing: `TTB/Models/Question.swift`, `TTB/Models/QuestionListShare.swift`, `TTB/Utilities/AppDeepLinkRouter.swift`.
- Swift services/views: `TTB/Services/QuestionListShareService.swift`, `TTB/Views/Main/SharedQuestionListViews.swift`, question card/detail views using `ShareLink`.
- Firebase web/function handlers: `functions/index.js`, `functions/questionListShares.js`, `firebase.json`.
- Associated domains: `TTB/TTB.entitlements`, `Website/.well-known/apple-app-site-association`.
- Tests: `Tests/QuestionListShareTests.swift`, `functions/questionListShares.test.js`, share/deep-link related tests.

## Workflow

1. Identify the link type:
   - Question share: `/q/{questionId}`.
   - Question-list share: `/l/{shareCode}`.
   - Custom scheme fallback: `ttbp://...`.
2. Verify canonical URL construction uses HTTPS public links and percent-encodes path components with `URLComponents` or equivalent URL APIs.
3. Trace the link end to end:
   - Swift `ShareLink` or service result.
   - Firebase Hosting rewrite in `firebase.json`.
   - Cloud Function preview/HTML response.
   - AASA route coverage.
   - `AppDeepLinkRouter` parsing and in-app destination.
4. For question-list sharing, confirm creator, recipient, guest/permanent-account, revoked/disabled, own-link, cap, and latest-reply snapshot states.
5. Keep visible UI states stable: no button width jumps when loading, no swallowed accept errors, and copy/selectable URL affordances where the link must be inspected.

## Validation

Run the narrowest relevant tests first:

```bash
npm test --prefix functions -- questionListShares.test.js
xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 12,OS=26.5' -only-testing:TTBTests/QuestionListShareTests test
```

When Hosting or AASA changes, also verify the generated/static files locally and state whether live deploy remains pending. Do not deploy without an explicit user request.

## Output

Finish with:

- Which link paths were changed or verified.
- Any required Firebase Hosting/Functions deploy step.
- Test results for Functions and Swift routing/model coverage.
