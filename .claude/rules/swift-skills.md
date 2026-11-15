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
| Any SwiftUI view — Apple's own SwiftUI guidance (with `swiftui-pro`) | `swiftui-specialist` |
| iOS 27 SwiftUI API: `reorderable`, swipe actions outside `List`, toolbar overflow, `@State` macro errors | `swiftui-whats-new-27` |
| An XCTest file, or moving a test to Swift Testing (with `swift-testing-pro`) | `modernize-tests`   |
| Profiling with Instruments or `xctrace` (with `ios-memory-perf`)  | `xctrace`           |
| App Intents, Shortcuts, Siri, widget configuration intents        | `app-intents-specialist`, `app-intents-whats-new-27` |

The five rows above under the style-guide row are Apple's own skills, exported from Xcode 27 with
`xcrun mcpbridge run-agent skills export` into `~/.claude/skills/` (2026-11-11). Their text says it supersedes
older training; when one disagrees with a community skill above, follow Apple's. Re-export after each Xcode update
(`--replace-existing`).

**Newer-iOS APIs go through `Backport`.** The deployment target is iOS 18.2, and `swiftui-whats-new-27`,
`app-intents-whats-new-27` and the Liquid Glass skills teach iOS 26/27-only API. Wrap each such API in the
existing backport system: `TTB/Utilities/Backport.swift` (`view.backport.<name>(…)`, or `Backport.<Name>` for
toolbar content), one `TTB/Utilities/Backport+<Feature>.swift` per API, with `if #available(iOS 26.0, *)` (or
27.0) inside it and a fallback for older iOS (the old look, or nothing when the feature is cosmetic). Do
not add a new `#available` check in a view; reuse or add a `Backport+` file. Example: `Backport+ToolbarSpacer.swift`.

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
  XCTest files to Swift Testing as a drive-by. Swift Testing does not support UI tests, so every
  file under `TTBUITests/` stays on XCTest.
- UI-observed model types are `@MainActor` when they mutate published state.
