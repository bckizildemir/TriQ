# Stabilization Refactor Audit

## Baseline

- Branch handoff completed before refactoring:
  - Preserved existing view/script work on `codex/settings-view-fix` with commit `249351b`.
  - Cherry-picked that backup commit onto `main` as `344436f`.
  - Verified and pushed `main` to `origin/main`.
  - Created `codex/stabilization-refactor` from the pushed `main`.
- Required gates were green before refactor work started:
  - `xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' test`
  - `cd functions && npm test`

## Non-Negotiable Constraints

- Preserve the current iOS 18.2 deployment target and existing iOS 26-compatible UI behavior.
- Do not redesign screens, change navigation structure, replace existing toolbar/sheet/full-screen-cover patterns, or alter accessibility identifiers during structural cleanup.
- Avoid adopting iOS 26-only APIs or Liquid Glass in this pass.
- Keep SwiftUI extractions behavior-preserving and covered by the existing UI tests where possible.

## High-Priority Findings

- Client writes can currently mutate aggregate question fields such as answer stats, respondent counters, and favorite arrays. These should move behind callable functions before Firestore rules are tightened.
- The simplified content-release model is mostly implemented, but scheduled/draft/canceled backend code and indexes still exist and create a competing operational path.
- Unit tests still launch against configured Firebase state in some paths. More service injection is needed so model tests can run without live project/session dependency.
- `QuestionService`, `BadgeModel`, and `AnswerProgressService` overlap on completion and badge-progress accounting. This makes answer-save behavior harder to reason about.
- Several production paths still use `print` for auth, Firestore, AI config, and background-save diagnostics. These should move to `Logger` or debug-gated logging.
- Firestore and Storage rules need stricter size, type, and ownership validation before expanding sharing or retention surfaces.

## Refactor Backlog

- Extract oversized SwiftUI views only when the resulting files preserve current layout, navigation, and identifiers.
- Introduce protocols for Firebase-backed services so models can be tested with deterministic fakes.
- Move answer-save and favorite-toggle integrity to Cloud Functions, then restrict direct client writes in Firestore rules.
- Finish retiring obsolete release lifecycle code, docs, and indexes.
- Add focused rules tests for owner checks, aggregate write denial, AI query limits, release admin writes, and Storage image access.

## Retention Expansion Backlog

- Improve the "What's New" experience with better release history and pending-release previews.
- Add clearer daily prompt status, streak context, badge-progress nudges, and notification preference copy.
- Expand category discovery after the stabilization branch is green.
- Defer broader AI/social expansion until the refactor lands.
