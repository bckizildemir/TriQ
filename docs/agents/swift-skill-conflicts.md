# Swift skill conflicts — open decisions

Status: all 7 decided and applied 2026-10-03, checked against Apple docs via sosumi (quotes under
each decision).

The Swift skills live in `~/.claude/skills/`, not in this repo. They load in **TTB and
CatCareCalendar (CCC)** alike, so each decision below changes both projects at once.
`~/.claude/agents/swift-reviewer.md` loads `swift-style-guide`, `swift-concurrency-pro`,
`swiftui-pro`, `swiftdata-pro`, `swift-testing-pro`, `swiftui-liquid-glass`,
`ios-navigation-chrome` and `ios-memory-perf`, so it receives both sides of conflicts 1, 3 and 4
in the same review. Conflict 2 reaches it only if `swiftui-ui-patterns` is ever routed (see 6).

Usage today (measured 2026-10-03, app targets only):

| | TTB (`TTB/`) | CCC (`CatCareCalendar/`) |
|---|---|---|
| Files with `DispatchQueue` | 5 | 0 |
| Files with `ObservableObject` | 22 | 0 |
| `*ViewModel` types | 4 | 2 |
| Swift language mode / deployment target | 5.0 / iOS 18.2 | 6.0 / iOS 18.4 |

## How the evidence was gathered

1. **Xcode's own agent documentation.** Xcode 27.0 (27A266) and Xcode 27.0 beta (27A5194o)
   ship byte-identical files in
   `Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/`
   (20 files, dated 2026-03-17 and 2026-06-06). Nothing newer is downloaded under
   `~/Library/Developer/Xcode/`. These files cover Swift 6.2 concurrency and Liquid Glass, but
   say nothing about GCD rules, view models, or `ObservableObject` vs `@Observable`.
2. **The web**, where Xcode was silent: Apple's SwiftUI documentation and swift.org (sources at
   the end).

---

## 1. Grand Central Dispatch

| Side | Text |
|---|---|
| `swift-style-guide/SKILL.md:32` | "Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency." |
| `swift-concurrency-pro/SKILL.md:35` | "Prefer Swift concurrency over Grand Central Dispatch for new code. GCD is still acceptable in low-level code, framework interop, or performance-critical synchronous work where queues and locks are the right tool – don't flag these as errors." |

**Evidence.**
- Xcode 27 `Swift-Concurrency-Updates.md` describes Swift 6.2 as "single threaded by default until
  you choose to introduce concurrency", main-actor-by-default as opt-in and "recommended for apps",
  and `@concurrent` for work that must leave the actor. It never forbids GCD.
- swift.org *Incremental Adoption* (Swift 6 migration guide) keeps queue-based code working
  during migration: a `DispatchSerialQueue` can back an actor's executor, and state that a
  dispatch queue guards can use `nonisolated(unsafe)` as a last resort.

**Recommendation: keep `swift-concurrency-pro`'s rule** (your stated preference, and what the
sources support). Change `swift-style-guide:32` to match it, for example: "Use Swift concurrency
for new code instead of `DispatchQueue.main.async()` and similar calls. GCD stays acceptable in
low-level code, framework interop, and synchronous queue- or lock-based work."
Effect: TTB's 5 `DispatchQueue` files stop being blanket findings; CCC has none.

**Decision (2026-10-03):** keep concurrency-pro's rule; `swift-style-guide:32` rewritten, with `@MainActor` (not
`MainActor.run`) as the target. Apple: Dispatch is a peer of Swift concurrency (*Improving app
responsiveness*); swift.org: "The ultimate goal should still be to apply `@MainActor`".

## 2. View models

| Side | Text |
|---|---|
| `swift-style-guide/SKILL.md:57` | "Place view logic into view models or similar, so it can be tested." |
| `swiftui-ui-patterns/SKILL.md:30` | "Use modern SwiftUI state (`@State`, `@Binding`, `@Observable`, `@Environment`) and avoid unnecessary view models." |

**Evidence.** Apple, *Managing model data in your app*: apply `@Observable` to the data model,
create the source of truth with `@State`, share it with `@Environment`, and use `@Bindable` for
bindings. The separation of data from views "improves testability". The article never uses the
term "view model"; it neither requires one per view nor bans one.

**Recommendation:** one merged rule close to Apple's wording, in `swift-style-guide` only:
"Keep logic that needs tests in `@Observable` model types (owned with `@State`, shared with
`@Environment`); do not add a view model to a view that has no such logic." Then delete the
view-model half of `swiftui-ui-patterns:30`. This fits TTB's `*Model` / `*Store` convention
(`CLAUDE.md` → Coding Style) and CCC's SwiftData `@Model` types.

**Decision (2026-10-03):** merged rule, applied to `swift-style-guide:57`; view-model half of
`swiftui-ui-patterns:30` deleted. Apple (Xcode, *Understanding and improving SwiftUI performance*):
"Move business logic and other non-UI work out of views to model types".

## 3. `ObservableObject` (one file, two strengths)

| Side | Text |
|---|---|
| `swift-style-guide/SKILL.md:26` | "Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts …" |
| `swift-style-guide/SKILL.md:42` | "Never use `ObservableObject`; always prefer `@Observable` classes instead." |

**Evidence.** Apple's *Managing model data* note points existing apps to the guide *Migrating
from the observable object protocol to the observable macro* — a migration path, not a ban.

**Recommendation:** delete line 42; line 26 already carries the rule, the reason, and the legacy
exception. Effect: TTB's 22 `ObservableObject` files are judged as legacy code, not as errors.

**Decision (2026-10-03):** `:42` deleted. Apple: "You don't need to make a wholesale replacement of the
ObservableObject protocol throughout your app"; `ObservableObject` is not deprecated.

## 4. Liquid Glass snippets without an availability gate

| Side | Text |
|---|---|
| `swiftui-liquid-glass/SKILL.md:35` | "Gate with `#available(iOS 26, *)` and provide a non-glass fallback." |
| `swiftui-liquid-glass/SKILL.md:54` | "Use these patterns directly and tailor shapes/tints/spacing." — two of the three snippets after it (`GlassEffectContainer`, `.glassProminent`) have no gate. |

**Evidence.** Xcode 27 `SwiftUI-Implementing-Liquid-Glass-Design.md` gives no iOS version or
`#available` note at all. Both repos target iOS 18.x, so an ungated snippet does not compile.

**Recommendation:** change line 54 to: "Tailor shapes/tints/spacing. Every snippet below needs
iOS 26; below that target, wrap it in the `#available(iOS 26, *)` gate with a fallback, as the
first snippet shows."

**Decision (2026-10-03):** applied. `GlassEffectContainer`, `glassEffect(_:in:)`, `.glassProminent` are all
iOS 26.0+. Also added Apple's limit rule to Core Guidelines: "Limit the use of Liquid Glass effects
onscreen at the same time."

## 5. Two performance skills with the same triggers

- `swiftui-performance-audit` (description): "diagnose slow rendering, janky scrolling, high
  CPU/memory usage … guidance for user-run Instruments profiling".
- `ios-memory-perf` (description): measure-first, "find-the-root-cause-then-widen", image decode,
  `body` derivations, SwiftData query cost.

Both repos route perf work only to `ios-memory-perf` (`CLAUDE.md` tables). The two skills can
still both trigger on the same request.

**Recommendation:** narrow `swiftui-performance-audit`'s description to "code-review-only audit
when no measurement is possible", or remove it.

**Decision (2026-10-03):** narrowed — description now says code-review-only, no measurement, and hands
reported symptoms to `ios-memory-perf`. Apple backs measure-first: "Use Instruments to detect
long-running view body calculations and frequent view updates".

## 6. Swift skills that no table routes

You want all Swift skills used. Neither `CLAUDE.md` routes `swiftui-ui-patterns` or
`swiftui-performance-audit`; CCC's `docs/swift-skill-trigger-setup.md` records that choice.
Each one carries an open conflict (2 and 5), so routing it first would load the conflict into
every Swift edit.

**Recommendation:** decide 2 and 5 first; then add a row for any skill that survives, in both
repos' `CLAUDE.md`, `.claude/rules/swift-skills.md`, and `CODING_STANDARDS.md`.

**Decision (2026-10-03):** route `swiftui-ui-patterns` (row: new screen or component; tab, route, or
sheet structure) in both repos' `CLAUDE.md`/`AGENTS.md`, `.claude/rules/swift-skills.md`, and
`CODING_STANDARDS.md`. `swiftui-performance-audit` stays unrouted.

## 7. "Target Swift 6.2" pins (low)

`swift-testing-pro/SKILL.md:25` and `swiftdata-pro/SKILL.md:25`: "Target Swift 6.2 or later,
using modern Swift concurrency." TTB builds in Swift 5 mode and CCC in Swift 6.0 mode. The
same pin in `swift-concurrency-pro` was already rewritten (2026-10-03) to read the project's
language mode first. The effect here is smaller: Swift Testing depends on the toolchain, not the
language mode.

**Decision (2026-10-03):** rewritten in both skills: read `SWIFT_VERSION` first, target the Swift 6 language
mode (6.0 or later), report Swift 6-only diagnostics as migration findings in a Swift 5 project.
"Swift 6.2" names a toolchain, not a language mode, so the pin now says 6.0. `swift-testing-pro` also
gets Apple's note that test functions run on an arbitrary task, so a test that touches main-actor
state needs `@MainActor`. Context: TTB plans to move to the Swift 6 language mode.

---

## Sources

- Xcode 27.0 agent docs: `…/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/Swift-Concurrency-Updates.md`, `SwiftUI-Implementing-Liquid-Glass-Design.md`
- Apple, [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- Apple, [Model data](https://developer.apple.com/documentation/swiftui/model-data)
- swift.org, [Swift 6 migration guide — Incremental Adoption](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/)
- Apple, [Updating an app to use strict concurrency](https://developer.apple.com/documentation/swift/updating-an-app-to-use-strict-concurrency)
