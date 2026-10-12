# Repository Guidelines

`AGENTS.md` is a copy of this file for Codex. Edit `CLAUDE.md`, then copy it to `AGENTS.md`.

## Swift skills are mandatory

Before you write or edit a Swift file under `TTB/`, `Tests/`, or `TTBUITests/`, invoke the
matching skill, then edit. This applies to one-line changes too: a small change to a `body` or an
`async` call is where these skills catch the most problems.

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
pass, or a review of image loading or body-read computed properties. `swiftdata-pro` does not
apply: this app persists through Firestore, not SwiftData.

## Project Structure & Module Organization
- `Documentation/` is the single source for architecture, AI, migration, deployment, and badge docs.

## Build, Test, and Development Commands
```bash
open TTB.xcodeproj
Scripts/xcb.sh build
Scripts/xcb.sh test --scheme TTBTests                                   # fast local loop: unit tests only
Scripts/xcb.sh test --scheme TTBTests --only TTBTests/FavoriteStoreTests # changed area
Scripts/xcb.sh test                                                     # full suite (unit + UI) once, before the PR
```
- Use the first command for day-to-day development in Xcode.
- Agents build and test through `Scripts/xcb.sh`, never a bare `xcodebuild`. The script holds a machine-wide lock, so builds from every worktree and from CatCareCalendar queue one at a time on this 16GB Mac; it shares one DerivedData and package checkout across worktrees, so Firebase compiles once. A run can wait minutes for the lock: give it a long Bash timeout or run it in the background. `Scripts/xcb.sh --help` lists the options.
- Two schemes. `TTBTests` is the inner loop: it builds the app and the unit test bundle only and skips the UI test target. `TTB` is the full run with unit and UI tests. Test the changed area with `--scheme TTBTests --only`; run the full `TTB` scheme once, before the PR. Neither scheme collects code coverage.
- A new worktree has no `TTB/Secrets.xcconfig` (gitignored), and the build fails at once without it. Copy `TTB/Secrets.xcconfig.template` to `TTB/Secrets.xcconfig` before the first `Scripts/xcb.sh` run. Do not commit `TTB/Secrets.xcconfig`.
- The baseline simulator is iPhone 12 on iOS 26.5; the script shuts down any other booted simulator before a test.
- To see a change in the app, build with the script, then install and launch the `.app` path it prints with xcodebuildmcp (`install_app_sim`, `launch_app_sim`). xcodebuildmcp's own `build_*`/`test_*` tools bypass the lock.
- `Scripts/xcb.sh` is shared with CatCareCalendar; keep the two copies identical.

```bash
cd Scripts/seed_questions && npm install && npm run seed
bash Scripts/check_model_conflicts.sh
bash Scripts/check_model_usage.sh Question
```
- These manage Firestore seed data and model-impact checks.

## Coding Style & Naming Conventions
- Follow Swift conventions: 4-space indentation, `PascalCase` for types, `camelCase` for properties/functions.
- Keep naming consistent with existing patterns: `*View` for SwiftUI views, `*Model` for state/models, `*Service` for external/data operations.
- `*Store` is the accepted name for a state type that owns a seam behind an injected protocol and coordinates async writes against it — `FavoriteStore`, `AnswerDraftStore`, `QuestionModerationStore`. Their ADRs (`docs/adr/0005`, `0007`) argue the boundary; use `*Model` for state with no seam of its own.
- Prefer `async/await`, and keep UI-observed model types `@MainActor` when they mutate published state.
- No repo-level SwiftLint/SwiftFormat config is committed; rely on Xcode formatting and existing file style.

## Testing Guidelines
Testing rules load from `.claude/rules/testing.md` when you work in `Tests/` or `TTBUITests/`. Read them before you write a test.

CI (`.github/workflows/ci.yml`) builds once with `build-for-testing` on scheme `TTB`, then runs the `TTBTests` unit tests with `test-without-building` and uploads `TestResults.xcresult` after the build step runs, pass or fail. It skips the iOS job for docs-only changes (`Documentation/`, `docs/`, `.claude/`, and Markdown in the repo root or `Scripts/`) and runs the `functions` job only for `functions/`, the Firestore and Storage rules, `firestore.indexes.json`, or `firebase.json`. The Release device build runs on push to `main` only. CI does not run UI tests.

Before you add or edit a live Firebase adapter — a type that calls the Firebase SDK — read `.claude/skills/ttb-live-adapter-tests/SKILL.md`.

## Commit & Pull Request Guidelines
- Current history follows mostly Conventional Commit prefixes: `feat:`, `fix:`, `fix(scope):`, `chore:`, `refactor:`.
- Keep commits small and single-purpose; use imperative summaries (example: `fix(badges): persist progress on answer save`).
- PRs should include: concise description, linked issue/task, validation steps run, and screenshots for UI changes.
- Explicitly call out Firebase-impacting changes (rules/indexes/seeding) in the PR description.

## Agent skills

### Project skills

Nine project skills live in `.claude/skills/` and ship with this repository. The Firestore database is fixed: `(default)`, Standard edition, `eur3`. Run `firebase-security-rules-auditor` after each `firestore.rules` change.

`.claude/skills/README.md` records the origin and the refresh policy of each of these 9 skills, names the one upstream snapshot commit behind the six vendored skills, and gives the commands that detect local edits since the import. The policy column is a decision, not a fact any command re-derives. Read that file before you refresh a vendored skill.

The eight mandatory Swift skills in the table above (`swiftui-pro`, `swiftui-ui-patterns`, `swift-concurrency-pro`, `swift-testing-pro`, `swiftui-liquid-glass`, `ios-navigation-chrome`, `ios-memory-perf`, `swift-style-guide`) are personal skills. `swift-style-guide` was written for iOS 26 / Swift 6.2; this project reports `IPHONEOS_DEPLOYMENT_TARGET = 18.2` and `SWIFT_VERSION = 5.0` (verified 2026-10-02), so treat its version numbers as the target for new code and flag any API the deployment target can't support. Each machine installs them in `~/.claude/skills`, and this repository does not ship them.

A user-level `PostToolUse` hook (`~/.claude/hooks/swift-skill-reminder.sh`, registered in `~/.claude/settings.json`) names the skills an agent has not loaded yet after an `Edit`/`MultiEdit`/`Write` on a `.swift` path. CatCareCalendar uses the same script. It fires in every project on this machine, in Herdr worktrees, and inside subagents. It never names `ios-memory-perf` — the table above is that skill's only route — and it names `swiftdata-pro` only for files that use SwiftData, so it stays silent on that skill here. It needs `jq`. It is not in the repo, so a fresh clone on another machine does not have it. The table above is the routing wherever the hook cannot fire — edits made through Bash or by the user in Xcode. See `docs/agents/swift-skill-triggers.md`.

`CODING_STANDARDS.md` points review agents (for example `code-review`, whose standards agent reads that file) at this file's conventions and the Swift skills.

### Matt Pocock skills

Matt Pocock's 27 skills (`implement`, `code-review`, `tdd`, `grilling`, …) are project skills in `.claude/skills/`, copied there by `npx skills` and pinned in `skills-lock.json` (2026-10-11, v1.3.1). Call them by bare name: `/implement`, not `/mattpocock-skills:implement`. The old `mattpocock-skills` plugin is turned off for this repo in `.claude/settings.json`, so each skill loads once. Matt's `code-review` replaces the built-in `/code-review` in this repo, and `implement` calls it by that name. Update with `npx skills@latest update -p`, then review the diff. Add one with `npx skills@latest add mattpocock/skills -a claude-code --copy -y -s <name> <name>`: names are space-separated; a comma-separated list installs nothing and prints no error. `.claude/skills/README.md` records their provenance.

### Issue tracker

Issues live as GitHub issues in the public `bckizildemir/TriQ` repo, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — root `CONTEXT.md` plus `docs/adr/`. See `docs/agents/domain.md`.

## Firebase objects

Fetch a Firebase object (`Firestore.firestore()`, `Functions.europeWest1`, `Storage.storage()`) inside the method that uses it, in every Swift file under `TTB/`. Do not store it. See `docs/agents/firebase-objects.md`.

## Security & Configuration Tips
- `TTB/Secrets.xcconfig` holds non-secret client configuration (see the template); the copy step is in the build section above.
- Never commit secrets or service account files (for example `Scripts/seed_questions/serviceAccountKey.json`).
- Confirm active Firebase project before running deploy/seed commands.
