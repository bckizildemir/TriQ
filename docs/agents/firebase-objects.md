# Fetch Firebase objects inside the method

The rule: fetch a Firebase object inside the method that uses it. Do not keep it in a stored,
lazy, or forwarding computed property.

Examples: `Firestore.firestore()`, `Functions.europeWest1`, `Storage.storage()`.

A method that uses Firestore more than once may bind it to one local `let db`. The SDK returns its
cached instance on each call, so a second fetch costs nothing.

## Scope

The rule covers every Swift file under `TTB/`, Services and Models. The Services follow it now
(TriQ#12, TriQ#74). `TTB/Models` does not follow it yet. TriQ#78 applies it there. Do not read this
doc as a claim that Models already comply.

## Why

1. **The actor region pin.** A stored Firebase object becomes state of the type that holds it. When
   that type is an actor or is `@MainActor`, the object stays in that isolation region. A method
   cannot send it out, for example into the `Sendable` `FirestoreListenerHandle`. A fresh object
   fetched in the method has no such pin.
2. **Firebase objects are not `Sendable`.** This holds for `Firestore`, `Functions`, and `Storage`
   in firebase-ios-sdk 11.7.0 (`Package.resolved`). Re-check on SDK upgrade. If a later SDK marks
   them `Sendable`, reason 2 stops and this rule may relax.

## Related

- `Functions.europeWest1` in `TTB/Services/FunctionsRegion.swift` is the one way to get the
  Functions client for the TTB region.
