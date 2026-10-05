# TriQ

TriQ (code name TTB) is an iOS app for short three-part entries. Each prompt asks for exactly three answers, so the app works as a favorites list, a light diary, and a conversation starter at the same time. Users collect prompts into question lists, answer them, add photos, earn badges, and share focused question lists with friends to compare answers side by side. An optional AI helper suggests answers when a user feels stuck.

Built with SwiftUI and Firebase (Auth, Firestore, Storage, Cloud Functions, Hosting).

## Requirements

- Xcode 26 or later
- iOS 18.2+ deployment target
- Node.js 22 and the Firebase CLI, only for the backend (`functions/`, rules, seeding)

## Getting started

```bash
git clone https://github.com/bckizildemir/TriQ.git
cd TriQ
cp TTB/Secrets.xcconfig.template TTB/Secrets.xcconfig
open TTB.xcodeproj
```

Pick the `TTB` scheme and an iOS simulator, then run.

`Secrets.xcconfig` holds non-secret client defaults only. AI provider keys never ship in the app: they live in Firebase Functions secrets. See [`Documentation/API_KEY_SETUP.md`](Documentation/API_KEY_SETUP.md).

### Use your own Firebase project

`TTB/GoogleService-Info.plist` points at the maintainer's Firebase project. Its API key is a client identifier restricted to this app's bundle ID, not a secret. For a fork, create your own Firebase project, replace the plist, and deploy the rules and functions:

```bash
firebase use --add
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase functions:secrets:set GROQ_API_KEY
firebase deploy --only functions
```

Seed prompts with `cd Scripts/seed_questions && npm install && npm run seed` (needs a service account key, which must never be committed).

## Tests

```bash
Scripts/xcb.sh test                                   # whole suite
Scripts/xcb.sh test --only TTBTests/FavoriteStoreTests
cd functions && npm test                              # Cloud Functions
```

Unit tests use Swift Testing; UI tests use XCTest. CI builds the app and all test targets on every push and pull request.

## Project layout

| Path | Contents |
| --- | --- |
| `TTB/` | The iOS app: `Views/`, `Models/`, `Services/`, `Utilities/` |
| `Tests/`, `TTBUITests/` | Unit and UI tests |
| `functions/` | Firebase Cloud Functions (AI proxy, sharing, moderation) |
| `Website/` | Firebase Hosting: landing, privacy, terms, share-link pages |
| `Scripts/` | Build lock wrapper, seeding, model-impact checks |
| `Documentation/` | Product, architecture, AI, and badge docs — start at [`Documentation/README.md`](Documentation/README.md) |
| `CONTEXT.md`, `docs/adr/` | Domain language and architecture decision records |

## Contributing

Issues and pull requests are welcome. Read [`CLAUDE.md`](CLAUDE.md) for code style, commit conventions, and PR expectations. Use Conventional Commit prefixes (`feat:`, `fix:`, `chore:`, `refactor:`), and call out any change to Firestore rules, indexes, or seeding in the PR description.

## License

[MIT](LICENSE)
