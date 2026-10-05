# TTB Question Seeding

Seeds `questions.json` into Firestore `questions` collection.

## Files
- `seed.js`: uses Firebase Admin SDK + `serviceAccountKey.json`
- `seed_with_cli_token.js`: uses your local Firebase CLI login token
- `sync_categories_with_cli_token.js`: updates existing seeded question category fields only
- `sync_with_cli_token.js`: updates existing Firestore question docs in place by matching old seeded text to new seeded text
- `backfill_release_announcement_state.js`: backfills legacy `isAnnounced` state for categories/questions and missing seeded-question `source`
- `backfill_question_moderation.js`: backfills moderation state and creator usernames for existing user-created questions
- `questions.json`: source dataset
- `questions.previous.json`: previous dataset snapshot used for safe in-place text migration

## Install
```bash
cd Scripts/seed_questions
npm install
```

## Option A: Seed with Service Account (`seed.js`)
1. Firebase Console -> Project Settings -> Service Accounts -> Generate key
2. Save key as `Scripts/seed_questions/serviceAccountKey.json`
3. Run:
```bash
node seed.js
node seed.js --clean
node seed.js --dry-run
```

## Option B: Seed with Firebase CLI Session (`seed_with_cli_token.js`)
```bash
firebase login
cd Scripts/seed_questions
node seed_with_cli_token.js
node seed_with_cli_token.js --clean
node seed_with_cli_token.js --dry-run
```

## Option C: Sync Existing Questions In Place (`sync_with_cli_token.js`)
Use this when prompt texts changed and you want to preserve existing question document IDs and any nested user answers.

```bash
firebase login
cd Scripts/seed_questions
node sync_with_cli_token.js --dry-run
node sync_with_cli_token.js
```

## Option C2: Sync Existing Question Categories Only (`sync_categories_with_cli_token.js`)
Use this when `questions.json` category assignments changed and existing answers/stats must stay untouched.

```bash
firebase login
cd Scripts/seed_questions
node sync_categories_with_cli_token.js --dry-run
node sync_categories_with_cli_token.js
```

## Option D: Backfill Legacy Release State (`backfill_release_announcement_state.js`)
Use this before the simplified release flow goes live so legacy categories/questions do not appear as newly pending content.

Safe run checklist:
1. Confirm the target project is `ttbp-9d652`.
2. Run a dry run first.
3. Only run the write command after reviewing the planned counts.

```bash
firebase login
firebase use ttbp-9d652
cd Scripts/seed_questions
node backfill_release_announcement_state.js --dry-run
node backfill_release_announcement_state.js
```

This script:
- backfills `categories.isAnnounced = true` when the field is missing
- backfills `questions.isAnnounced = true` when the field is missing
- backfills `questions.source = "seeded"` when the field is missing

## Option E: Backfill User-Created Question Moderation (`backfill_question_moderation.js`)
Use this before enforcing moderated Trio publishing in production.

```bash
cd Scripts/seed_questions
node backfill_question_moderation.js --dry-run
node backfill_question_moderation.js --commit
```

This script:
- sets missing user-created `moderationStatus` to `approved`
- sets missing `featuredPlacement` to `none`
- fills missing `creatorUsername` from `users/{createdBy}.username` when available

## `--clean` Warning
`--clean` deletes all existing docs in `questions`. Use only in development or controlled migration windows.

If your production project already has user answers under question documents, prefer `sync_with_cli_token.js` over `--clean`.

## Question Format
```json
{
  "text": "Bugün seni en çok mutlu eden şey neydi?",
  "category": "Daily",
  "contentId": "daily-bugun-seni-en-cok-mutlu-eden-sey-neydi",
  "localizedTexts": {
    "tr": "Bugün seni en çok mutlu eden şey neydi?",
    "en": "What made you happiest today?"
  },
  "answers": [],
  "favoriteUserIds": []
}
```

## Valid Categories
`Daily`, `Personal`, `SelfDiscovery`, `Relationships`, `SocialLife`, `Career`, `Health`, `Goals`, `Creativity`, `Food`, `MoviesTV`, `Books`, `Music`, `Games`, `Travel`, `Style`, `DigitalLife`, `Hobbies`, `Childhood`, `Home`, `Humor`, `Boundaries`, `Recommendations`, `Photography`
