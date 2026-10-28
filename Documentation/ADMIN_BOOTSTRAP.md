# Admin Bootstrap

How the first admin account comes to exist. This file records a fact. It is not an ADR.

## The admin check

- The admin check is `users/{uid}.isAdmin == true` (`isAdmin()` in `firestore.rules`).
- Cloud Functions read the same field (`userIsAdmin` in `functions/index.js`).
- The app only reads the field (`ProfileModel`, `AdminAccessGuardView`). Nothing in `TTB/` writes `isAdmin`.

## What a client can and cannot do

- A regular user cannot set `isAdmin`. The `create` rule refuses it. The `update` whitelist does not include it.
- An existing admin can change `isAdmin` on a `users/{uid}` document from a client. The rule allows only the keys `isAdmin` and `updatedAt`.
- So the first admin must be set outside the rules.

## Set the first admin

The project owner does this. The Firestore database is `(default)` in the project named in `.firebaserc`.

1. Make sure the user signed in to the app once. The `users/{uid}` document must already exist.
2. Find the uid in the Firebase console, under Authentication > Users.
3. Open the `users/{uid}` document in the Firebase console, `(default)` database.
4. Edit the field `isAdmin`. Set it to the boolean `true`. Add the field if it is not there.

The Admin SDK is an alternative. It bypasses the rules. Run a one-off script with service account credentials that sets `isAdmin: true` (and `updatedAt`) on the `users/{uid}` document. Never commit the service account file.

The original surface the owner used for the live admin was not found in the repository or its git history. No bootstrap script exists. The console and the Admin SDK are the documented methods.

## Rules

- No hardcoded admin email exists. Do not add one.
- A self-service admin path needs its own ADR first.

## Tests

The emulator tests in `functions/rules-emulator/securityRules.spec.js` prove that self-promotion is refused: self-create, delete and re-create, and self-update.
