# Trio User-Created Prompts

## Summary
Trio is a community prompt feed with a focused creation flow. Users can draft a Trio-style question with AI support, edit the final wording, submit it for review, and answer approved prompts from the community.

## V1 Decisions
- Approved prompts are public to authenticated users.
- Approved prompts live only in the Trio tab feed for now.
- Submission requires a non-anonymous account.
- Submitted prompts enter pending review before public display.
- AI is used to draft one question, not to return three answers.
- Admin mode is deprecated in the app UI, but admin-only codepaths still exist in the repo.

## Data Contract
- `questions/{questionId}` remains the source of truth.
- Added `source` to question documents:
  - `seeded`
  - `userCreated`
- User-created Trio prompts store:
  - `text`
  - `category`
  - `source = userCreated`
  - `createdAt`
  - `createdBy`
  - `moderationStatus = pending | approved | rejected`

## UX Shape
- Toolbar create action in Trio:
  - opens a sheet for permanent accounts
  - opens account upgrade/sign-in prompt for guest accounts
- Creation sheet:
  - multiline question-or-idea input
  - category selection
  - AI question-ideas action
  - editable final question
  - submit-for-review action
- Public feed below:
  - approved prompts only
  - vertical scroll
  - opens existing question answer flow

## Security Notes
- Firestore rules no longer rely on the temporary blanket-open debug rule.
- Permanent authenticated users can create only their own pending `userCreated` question documents.
- Existing answer and favorite updates continue to use the `questions` collection.
