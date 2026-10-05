---
paths:
  - "TTB/**/*.swift"
  - "Tests/**/*.swift"
  - "TTBUITests/**/*.swift"
---

# Swift work requires a Swift skill

You have just read a Swift file in this repo. Before you write or edit any Swift here,
invoke the matching skill. Load it first, then edit. Do not skip this because the change
looks small — a one-line change to a `body` or an `async` call is exactly where these
skills catch problems.

| You are touching                                          | Invoke                  |
| --------------------------------------------------------- | ----------------------- |
| Any SwiftUI view, layout, or `@State`/`@Observable` code   | `swiftui-pro`           |
| A new screen or component; tab, route, or sheet structure  | `swiftui-ui-patterns`   |
| `async`/`await`, `Task`, actors, `Sendable`, `@MainActor`  | `swift-concurrency-pro` |
| Any test file — UI tests stay on XCTest                    | `swift-testing-pro`     |
| `glassEffect`, `GlassEffectContainer`, iOS 26 chrome       | `swiftui-liquid-glass`  |
| Navigation titles, toolbars, `ToolbarSpacer`               | `ios-navigation-chrome` |
| Anything perf-shaped: scroll, memory, launch, image decode | `ios-memory-perf`       |
| Any Swift file — modern-API choice over legacy, naming, structure | `swift-style-guide` |

More than one row can apply — invoke each that does, and `swift-style-guide` applies to every Swift
edit. `ios-memory-perf` is the one exception to
"load it before you edit": it is measure-first, so run it on a reported symptom, a deliberate perf
pass, or a review of image loading or body-read computed properties.

`swiftdata-pro` does not apply to this repo. TTB persists through Firestore and has zero
`import SwiftData`. Do not invoke it and do not propose SwiftData migrations unasked.

## Repo facts these skills should know

- Deployment target is iOS 18.2, so iOS 26 API needs an availability guard. Three files
  already use Liquid Glass — follow the shim pattern they establish rather than a new one.
- Both test frameworks are live under `Tests/`. Match the file you are editing; do not convert
  XCTest files to Swift Testing as a drive-by. Swift Testing does not support UI tests, so all
  14 files under `TTBUITests/` stay on XCTest.
- UI-observed model types are `@MainActor` when they mutate published state.
