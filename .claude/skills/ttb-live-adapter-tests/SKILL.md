---
name: ttb-live-adapter-tests
description: Use when adding or editing a TTB live Firebase adapter — a type that calls the Firebase SDK (snapshot listeners, httpsCallable, document reads and writes, Storage, Auth listeners) — or when moving logic out of a fake-tested type into one.
metadata:
  short-description: Keep live Firebase adapter logic testable without Firebase
---

# TTB Live Adapter Tests

A **live adapter** is the type behind a seam that calls the Firebase SDK: `FavoriteService`,
`QuestionListShareService`, `LiveBadgeStore`, and the like. Tests swap it for a fake, and no Swift
test talks to Firestore or the emulator. So code inside an adapter runs in no test.

The gap opens silently. Logic that sat in a fake-tested type (a store, a model) is covered; move it
into the adapter and the fake no longer runs it, yet the suite stays green.

## The rule

Keep the adapter **humble**: the Firebase closure forwards raw values to a plain function and does
nothing else. Every mapping, filter, error mapping, path parse, and actor hop lives in that plain
function, and a test calls it without Firebase.

1. List the logic your change puts inside or beside a Firebase closure: decoding and `compactMap`,
   error mapping, response guards on a callable's `data`, path parsing such as
   `document.reference.parent.parent`, and `Task { @MainActor }` hops.
2. Move it into a `static` function that takes plain values: document ids with `[String: Any]`
   data, an `Error?`, a callable's `[String: Any]` payload, and the callback.
3. Test that function in `Tests/` with Swift Testing. Cover valid documents, an invalid document
   that is dropped, a missing snapshot, an error, and the isolation the callback runs on. A test
   that waits on a callback carries a `.timeLimit`, so a broken hop fails instead of hanging.
4. The one line left untested is the SDK call that registers the closure. Name it in the PR's
   validation steps, with a manual check a person can run.

Done when every line of logic inside a Firebase closure in your diff is reached by a test that
needs no Firebase.

## Pattern

`FavoriteService.deliverSnapshot` in `TTB/Services/FavoriteService.swift`, tested by
`Tests/FavoriteSnapshotDeliveryTests.swift` (PR #40). The `addSnapshotListener` closure only
forwards to it. That test file still lacks the `.timeLimit` from step 3 until #41 adds it; give
yours one.
