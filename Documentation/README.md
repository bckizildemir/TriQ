# Documentation Hub

This folder contains all project-level documentation that was previously scattered across the repository.

## What to Read First
- `PRD.md`: product-level requirements and current user-facing scope, covering the app as a mix of favorites, diary/notebook, and conversation-starter prompts.
- `TTB_AI_Architecture_Analysis.md`: current app architecture and data flow.
- `TTB_AI_Technical_Specification.md`: implementation-level spec for the current product state.
- `AI_Integration_Documentation.md`: AI feature behavior and integration details.
- `Badge_System_Documentation.md`: badge progress logic and Firestore data model.
- `Question_List_Sharing_UX.md`: Shared tab hub (received + sent lists) and side-by-side comparison flows.

`PRD.md` defines product requirements; technical/architecture docs define implementation details.

## AI Docs
- `AI_API_Reference.md`: models, services, and runtime limits.
- `AI_PROVIDER_MIGRATION.md`: Groq/OpenRouter provider abstraction and migration notes.
- `AI_Integration_Research.md`: historical research and current recommendation context.
- `AI_User_Guide.md`: end-user behavior for the AI tab.
- `AI_Deployment_Guide.md`: release and backend rollout checklist.
- `API_KEY_SETUP.md`: local and CI key setup.

## Operations & Change Logs
- `BADGE_SYSTEM_IMPLEMENTATION_SUMMARY.md`: delivered badge system scope.
- `FIXES_APPLIED.md`: important bug fixes and cleanup history.
- `QUESTION_LIST_SHARING_AUDIT.md`: read-only audit of the sharing feature — rules/privacy findings, listener race, and service-seam design assessment.
- `ARCHITECTURE_DEEPENING_AUDIT.md`: open architecture backlog (`AD-1`…`AD-7`, `FIX-1`…`FIX-5`) — friction, deletion-test verdicts, and how to pick a candidate up. Start here for refactor work.

## Onboarding
- Post-auth onboarding is versioned via `AppConfig.onboardingVersion` (currently **v2**).
- Flow: welcome → example card preview → value highlights → sharing comparison → permissions + legal consent.
- Bumping `onboardingVersion` re-shows onboarding for users who completed an earlier version.

## Related Operational Files Outside This Folder
- Firebase rules: `firestore.rules`, `storage.rules`, `firestore.indexes.json`
- Seeding docs: `Scripts/seed_questions/README.md`
- Contributor guide: `AGENTS.md`
