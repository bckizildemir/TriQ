# Public list share previews show question text only

Public list share pages render up to the first three currently shareable question texts and categories for a shared list, plus a remaining-count indicator when the list has more questions. They never render owner answers, recipient answers, answer snapshots, or recipient metadata.

This keeps link previews useful enough for recipients to recognize the list before opening the app, while preserving the product boundary that answers are only available inside the accepted in-app share flow. The preview reads current public/approved question documents instead of stored share snapshots so web pages do not expose stale private answer state or require a Firestore schema migration.
