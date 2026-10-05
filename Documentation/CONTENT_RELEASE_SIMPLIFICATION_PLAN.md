# Content Release Simplification Plan

## Working Rules
- This plan will be completed progressively across multiple implementation passes. Do not assume it will be finished in one session.
- If you complete a task or phase, update this document, mark the relevant checklist items done, and add a short completion note in the plan itself.
- Use this file as the single long-running source of truth for this work. Do not create side plans unless this document explicitly requires them.
- Status legend:
  - `[ ]` not started
  - `[~]` in progress
  - `[x]` complete
- Checklist items can be marked `[x]` only when code, verification, and cleanup for that item are complete.
- If the working context becomes constrained, stop, update this document with the current state, and let the next pass continue from here.
- When a phase is finished, update its local `Completion note:` line and append a short `Done` entry to the `Completion Log` section at the bottom.

## Goal and Success Criteria
The goal is to simplify the current content-release and push-notification workflow so that new categories and seeded questions can be announced through a single, easy-to-manage admin flow without losing the existing push opt-in model or the user-facing "What's New" experience.

Success criteria:
- New categories and seeded questions become pending automatically when created.
- Admin can review pending content, optionally edit localized notification copy, and send one update covering all pending content.
- Backend publishes one immutable release record for each send, uses it for push delivery and "What's New", and marks included content as announced.
- Legacy content without explicit announcement state is safely treated as already announced.
- Manual selection, draft, scheduled, and canceled release workflow are removed from the simplified path.
- Swift changes follow the applicable Swift-focused skills listed in this document.

## Current State
The current system already has a working push-notification foundation:
- FCM device registration and per-device opt-in are handled through `NotificationService` and `notificationDevices`.
- Push tap handling already routes users into the app through `releaseId`.
- `contentReleases` already exists and powers the current "What's New" detail flow.

The current complexity comes from the release workflow:
- Admin must create a separate release record in addition to creating categories or questions.
- Admin must manually choose which categories and questions are included in a release.
- The release model includes `draft`, `scheduled`, `published`, and `canceled` states.
- A scheduled dispatcher exists for delayed publishing.
- Announcement state is partially inferred from `announcedAt` and `announcedInReleaseId`, but legacy seeded content is inconsistent and older seed flows may miss fields needed for reliable automation.

## Target Architecture
The simplified architecture keeps the notification foundation and removes workflow overhead:
- Keep the current FCM device registration and opt-in model.
- Treat `contentReleases` as published history only, used to support push tap handling and the "What's New" screen.
- Introduce explicit `isAnnounced: Bool` state for categories and questions.
- New categories and seeded questions start as pending with `isAnnounced = false`.
- Admin uses one simplified release screen that:
  - shows pending category and question counts
  - shows sample pending content
  - pre-fills editable TR/EN copy using automatic suggestion logic
  - publishes all pending content in one action
- Backend exposes one simplified callable:
  - `publishPendingContentRelease({ localizedTitle?, localizedBody? })`
- Backend gathers all pending content automatically, sends push notifications, creates one published release record, and marks included content as announced.
- The user flow remains:
  - push received
  - user taps notification
  - app opens the published release by `releaseId`
  - "What's New" renders categories and questions from that release

## Swift-Pro Compliance
All Swift implementation work under this plan must follow the relevant Swift-focused skills available in this workspace.

Required skill alignment:
- Use `swiftui-pro` for SwiftUI and view-layer changes.
- Use `swift-concurrency-pro` for async/service/backend-facing Swift code.
- Use `swift-testing-pro` for Swift test additions or updates.

Notes:
- There is no single `swift-pro` skill in this workspace.
- For this plan, "swift-pro compliant" means using the applicable concrete Swift skills above for each Swift change.
- If a later phase introduces SwiftData-specific work, use `swiftdata-pro` in addition to the above where relevant.

## Phases

### Phase 1: Data Model and Migration
Intent: Make announcement state explicit and stable so the rest of the simplification can rely on deterministic pending/announced behavior.

Checklist:
- [x] Add `isAnnounced: Bool` to category models, Firestore mapping, and any affected tests.
- [x] Add `isAnnounced: Bool` to question models, Firestore mapping, and any affected tests.
- [x] Preserve `announcedAt` and `announcedInReleaseId` in all model and write paths.
- [x] Update admin category creation so newly created categories start with `isAnnounced = false`.
- [x] Update admin seeded-question creation so newly created seeded questions start with `isAnnounced = false`.
- [x] Ensure edit flows preserve existing announcement fields and do not accidentally reset announcement state.
- [x] Update seed scripts so newly created seeded questions write `isAnnounced = false`.
- [x] Update seed scripts so legacy field expectations remain stable and announcement-related fields are never reset during non-creation updates.
- [x] Add a migration path that backfills state-less legacy categories as `isAnnounced = true`.
- [x] Add a migration path that backfills state-less legacy questions as `isAnnounced = true`.
- [x] Backfill missing legacy seeded-question `source` where required for release eligibility logic.
- [x] Document how to run the migration safely against the intended Firebase project.

Acceptance criteria:
- Categories and questions have an explicit, test-covered `isAnnounced` field.
- Existing `announcedAt` and `announcedInReleaseId` values are preserved.
- Newly created admin and seeded content becomes pending by default.
- Legacy content without announcement state does not flood the first simplified release.
- Legacy seeded content has a stable `source` value where the simplified backend depends on it.

Dependencies:
- None. This phase should land before backend or admin simplification work depends on explicit pending state.

Completion note: Explicit `isAnnounced` state now exists in Swift models, admin create/edit flows, Firestore rules, legacy/manual publish compatibility, and seed tooling. Added `Scripts/seed_questions/backfill_release_announcement_state.js` plus README run steps for safe legacy backfill. Remaining Phase 1 follow-up is live Firebase migration execution and its verification.

### Phase 2: Backend Publish Flow
Intent: Replace the current manual release-lifecycle backend with one callable that publishes all pending content in a single pass and records a published release for app consumption.

Checklist:
- [x] Add `publishPendingContentRelease({ localizedTitle?, localizedBody? })` to Cloud Functions.
- [x] Move release-content selection to the backend so it gathers all pending categories automatically.
- [x] Move release-content selection to the backend so it gathers all pending seeded questions automatically.
- [x] Reuse or adapt automatic copy generation so the callable can accept admin-edited TR/EN copy without reintroducing manual selection complexity.
- [x] Create one published `contentReleases` record per send containing localized title/body, included category IDs, included question IDs, and publication metadata.
- [x] Mark included categories as announced in the same publish flow.
- [x] Mark included questions as announced in the same publish flow.
- [x] Keep `contentReleases` usable as published history for the current "What's New" experience.
- [x] Ensure empty-pending publish attempts are safe and return a clear no-op response.
- [x] Ensure repeat publish attempts do not duplicate already announced content.
- [x] Remove or retire obsolete callable/backend paths tied to manual release ID publishing.
- [x] Remove or retire scheduled-dispatch logic tied to the old simplified-disabled release lifecycle.

Acceptance criteria:
- Admin no longer needs to create a release record first or choose content manually.
- Publishing all pending content is possible through one backend entrypoint.
- Publishing creates a valid immutable published release record.
- Included content is marked announced exactly once.
- Empty-pending and repeat-safety behavior are defined and verified.

Dependencies:
- Phase 1 explicit announcement state must be available first.

Completion note:
Simplified backend publish flow now exists in Cloud Functions via `publishPendingContentRelease`, with backend-owned pending selection, automatic copy generation plus admin override merging, published release record creation, and same-pass announcement marking. Added targeted function tests for happy-path/no-op/repeat safety, wired `ContentReleaseService` to the new callable for admin UI use, and removed the retired manual publish callable plus scheduled dispatcher from `functions/index.js`. Focused Functions tests passed after the cleanup.

### Phase 3: Admin UI Simplification
Intent: Replace the current release-management UI with a single operational screen focused on pending content, editable copy, and one send action.

Checklist:
- [x] Remove manual category selection UI from the admin release flow.
- [x] Remove manual question selection UI from the admin release flow.
- [x] Remove draft-oriented controls from the simplified admin release flow.
- [x] Remove scheduling-oriented controls from the simplified admin release flow.
- [x] Show pending category and question counts in the admin UI.
- [x] Show a concise preview or sample list of pending categories and questions so admins can confirm what will be sent.
- [x] Pre-fill editable TR/EN title and body using automatic suggestion logic.
- [x] Keep admin override capability so suggested copy can be edited before send.
- [x] Expose one primary `Send Update` action that calls the simplified backend publish flow.
- [x] Keep a published-history list so admins can review what was already sent.
- [x] Update user-facing and admin-facing localization strings affected by the simplified UI.

Acceptance criteria:
- Admin can understand pending content at a glance.
- Admin can send all pending content without manual inclusion or lifecycle management.
- Admin can edit the suggested localized copy before sending.
- Published history remains visible after the simplification.

Dependencies:
- Phase 2 backend callable and pending-state logic must be available for the new primary action.

Completion note:
Admin release management is now reduced to one pending-content screen in SwiftUI. The old manual category/question selection sheet, draft controls, and scheduling controls were removed from the operational path; the screen now shows pending counts and sample content, pre-fills editable TR/EN copy from the shared suggestion logic, publishes through `publishPendingContentRelease`, and keeps published history visible. Added a backward-safe `ContentRelease` status fallback so legacy release records stay visible in history, and extended release model tests. Full `xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' test` passed after the UI simplification landed. Remaining follow-up is the targeted admin-flow verification items listed under `Test and Verification`, plus repo/backend cleanup in later phases.

### Phase 4: Client Consumption
Intent: Preserve the existing app-side notification experience while adapting it to the simplified publishing model.

Checklist:
- [x] Keep push payload handling based on `releaseId`.
- [x] Keep push tap routing into the app through the existing notification presentation path.
- [x] Ensure the "What's New" detail view still resolves categories correctly from the published release record.
- [x] Ensure the "What's New" detail view still resolves questions correctly from the published release record.
- [x] Verify the simplified release data shape is sufficient for current app rendering needs.
- [x] Update client-side code only where required to match the simplified backend contract.

Acceptance criteria:
- A published update still opens correctly from a push tap.
- The detail screen still renders the categories and questions included in the published release.
- No new manual release-selection concepts leak into the client.

Dependencies:
- Phase 2 published release record shape must be finalized first.

Completion note:
Client release consumption remains `releaseId`-driven, with no new lifecycle concepts added to the app path. Hardened `ContentReleaseDetailViewModel` so related-content fetch failures clear stale state instead of showing partial release content, added a small notification payload parser helper for direct `releaseId` verification, and added focused Swift Testing coverage for payload parsing plus published release detail loading. Focused `xcodebuild` verification passed for `ContentReleaseClientFlowTests` and `NotificationReleaseModelsTests` on iPhone 16 iOS 18.5.

### Phase 5: Cleanup
Intent: Remove obsolete code, UI, and operational assumptions so the simplified model is the only supported workflow going forward.

Checklist:
- [x] Remove obsolete release states that are no longer part of the simplified path.
- [ ] Remove obsolete admin UI code tied to manual content selection.
- [ ] Remove obsolete admin UI code tied to draft, scheduled, or canceled lifecycle behavior.
- [x] Remove obsolete backend code paths that support the retired lifecycle.
- [ ] Remove obsolete localization strings if they are no longer referenced.
- [ ] Update related operational or project documentation if the simplified workflow changes maintenance expectations.
- [x] Review Firestore rules, function contracts, and seed tooling for stale assumptions left by the old model.

Acceptance criteria:
- The old manual-selection and scheduling workflow is not left half-supported.
- The repository no longer suggests multiple competing ways to publish content updates.
- Documentation and operational guidance match the simplified implementation.

Dependencies:
- Phase 1 through Phase 4 must be sufficiently stable to identify what is truly obsolete.

Completion note:
Scheduled release dispatch and legacy existing-release publishing have been removed from the exported Functions surface and release publisher module. The stale scheduled-release composite index was removed, and Functions tests now cover only the retained `publishPendingContentRelease` path for release publishing.

## Test and Verification
The following checks must be covered as implementation progresses:

Data model and migration:
- [x] Model round-trip coverage for `isAnnounced` on categories.
- [x] Model round-trip coverage for `isAnnounced` on questions.
- [ ] Migration verification for legacy categories with no announcement state.
- [ ] Migration verification for legacy questions with no announcement state.
- [ ] Migration verification for missing legacy seeded-question `source`.

Backend publish flow:
- [x] Happy-path verification for publishing pending content.
- [x] Verification that no-op publish behaves safely when there is no pending content.
- [x] Verification that repeated publish attempts do not resend already announced content.
- [x] Verification that published release records contain the expected IDs and localized copy.
- [x] Verification that included content is marked announced after publish.

Admin UI:
- [ ] Verification that pending summary counts are accurate.
- [ ] Verification that pending sample content matches the automatic selection logic.
- [ ] Verification that suggested TR/EN copy appears correctly.
- [ ] Verification that admin-edited copy is respected by the publish flow.
- [ ] Verification that the `Send Update` action behaves correctly on success and failure.

Client consumption:
- [x] Verification that push tap opens the correct published release.
- [x] Verification that the "What's New" screen renders included categories correctly.
- [x] Verification that the "What's New" screen renders included questions correctly.

Repository hygiene:
- [x] Verification that obsolete release-management code is removed or clearly retired.
- [ ] Verification that docs and operational scripts reflect the simplified model.

## Assumptions and Defaults
- Keep the current FCM device registration and opt-in model.
- Use one master plan file, not split docs.
- File name is `CONTENT_RELEASE_SIMPLIFICATION_PLAN.md`.
- Auto-generate notification copy, but allow admin edits before sending.
- Include all pending content automatically in each send; no manual inclusion/exclusion.
- Treat legacy content without announcement state as already announced.
- Keep `contentReleases` as published history for the current push tap and "What's New" flow.
- Remove draft, scheduled, and canceled workflow from the simplified operational path.
- Prefer additive, backward-safe migration steps before removing obsolete code.

## Completion Log
- 2026-03-28 | Codex | Created master living plan document | Done: initial implementation plan scaffold added to `Documentation/CONTENT_RELEASE_SIMPLIFICATION_PLAN.md`.
- 2026-03-29 | Codex | Implemented the first simplified backend publish slice | Done: added `publishPendingContentRelease`, backend pending selection/copy generation, release creation + announcement marking, function tests, and Swift service wiring.
- 2026-03-29 | Codex | Simplified the admin release UI around pending-content publishing | Done: replaced the manual draft/schedule release manager with a single pending-content send flow, updated release-history compatibility, refreshed admin localization copy, added legacy-release coverage, and passed the full iPhone 16 iOS 18.5 `xcodebuild ... test` suite.
- 2026-03-29 | Codex | Verified and hardened simplified client release consumption | Done: kept `releaseId`-based routing, tightened release-detail failure handling, added Swift Testing coverage for payload parsing and published release loading, and passed focused iPhone 16 iOS 18.5 release-flow tests.
- 2026-03-29 | Codex | Retired the old manual release publish backend path | Done: removed the legacy `publishContentRelease` callable and scheduled dispatcher, trimmed unused client release-service methods, and passed both Functions node tests and focused iPhone 16 iOS 18.5 release-flow tests.
- 2026-05-18 | Codex | Completed scheduled-release cleanup during stabilization refactor | Done: removed the scheduled dispatcher export, retired existing-release publishing helpers/tests, removed the stale scheduled release index, and kept `publishPendingContentRelease` as the sole backend release publishing path.
