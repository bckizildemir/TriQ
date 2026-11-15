---
paths:
  - "Tests/**"
  - "TTBUITests/**"
---

# Testing

- `Tests/` mixes Swift Testing and XCTest (match the file you are editing); every UI test in `TTBUITests/` is XCTest. `Tests/Support/` holds shared fakes and mocks, not test cases.
- Name test files `*Tests.swift`. Name XCTest methods `test...`; name Swift Testing functions with `@Test` and a descriptive camelCase name, no `test` prefix (`@Test func raisedFlagPresentsTheSheetOnce()`).
- Add/extend tests for model serialization, Firestore mapping, async flows, and edge cases (auth state changes, empty data, invalid input).
