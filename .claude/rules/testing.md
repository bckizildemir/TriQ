---
paths:
  - "Tests/**"
  - "TTBUITests/**"
---

# Testing

- Most of the suite is `XCTest`, including every UI test in `TTBUITests/`; a few files in `Tests/` use Swift Testing. `Tests/Support/` holds shared fakes and mocks, not test cases.
- Name test files `*Tests.swift`. Name XCTest methods `test...`; name Swift Testing functions with `@Test` and a descriptive camelCase name, no `test` prefix (`@Test func raisedFlagPresentsTheSheetOnce()`).
- Add/extend tests for model serialization, Firestore mapping, async flows, and edge cases (auth state changes, empty data, invalid input).
- If tests are not attached to a test target locally, create/attach a `TTBTests` unit test target in Xcode before running `xcodebuild ... test`.
