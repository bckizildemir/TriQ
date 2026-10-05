---
name: ttb-firebase-functions-debugging
description: Use when debugging TTB Firebase callable functions, Firestore rules or indexes, Cloud Functions deployment/runtime errors, permission failures, INTERNAL errors, auth-dependent data flows, or Swift service-to-Functions integration. This is repo-specific and complements general Firebase skills by pointing at TTB's functions, rules, Swift services, tests, and validation commands.
metadata:
  short-description: Debug TTB Firebase and callable flows
---

# TTB Firebase Functions Debugging

Use this for TTB bugs where Swift calls Firebase Functions or Firestore and the symptom is a failed save, permission error, missing data, `INTERNAL`, missing index, auth mismatch, or live/emulator behavior difference.

## Core Map

- Swift callers: `TTB/Services/*Service.swift`, especially `QuestionService`, `QuestionListService`, `QuestionListShareService`, `ContentReleaseService`, `AIService`, `FavoriteService`, `UsernameService`, and `AnswerImageSuggestionService`.
- Cloud Functions entrypoints: `functions/index.js`.
- Extracted function logic/tests: `functions/*.js` and `functions/*.test.js`.
- Firestore policy/config: `firestore.rules`, `firestore.indexes.json`, `storage.rules`.
- Firebase setup/docs: `firebase.json`, `functions/package.json`, `Documentation/API_KEY_SETUP.md`, `Documentation/AI_Deployment_Guide.md`.

## Workflow

1. Start with the failing user flow and identify the exact Swift service method and callable name.
2. Trace the request payload from Swift to `functions/index.js`, then into the helper module.
3. Check auth assumptions: anonymous vs permanent user, admin-only paths, owner/member checks, and expected `context.auth`/`request.auth` fields.
4. Check Firestore rules and indexes when the error mentions permission, missing data, query failure, or index creation.
5. Prefer targeted function tests before app builds:

```bash
npm test --prefix functions -- <test-file>
```

6. For Swift-side mapping/model behavior, add or run focused XCTest targets:

```bash
xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 12,OS=26.5' -only-testing:TTBTests/<TestClass> test
```

7. For integration confidence, run:

```bash
npm test --prefix functions
xcodebuild -project TTB.xcodeproj -scheme TTB -configuration Debug build
```

## Checks

- Do not assume a live Firebase index exists just because it is in `firestore.indexes.json`; mention deploy/build state if the fix depends on it.
- Do not deploy or seed data unless explicitly asked. If needed, first confirm active project should be `ttbp-9d652`.
- Keep user-facing error mapping in Swift and callable error codes aligned.
- For `INTERNAL`, inspect thrown non-`HttpsError` paths, missing env/secrets, payload shape mismatches, and unhandled parser assumptions.
- For permission failures, compare the callable admin path and direct client Firestore rules. TTB often routes writes through callables to keep client rules tighter.

## Output

Finish with:

- Root cause and files changed or inspected.
- Validation commands and pass/fail result.
- Any Firebase deploy/index/secret step the user must run separately.
