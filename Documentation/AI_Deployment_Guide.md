# TTB AI Deployment Guide

## Release Checklist
- Validate `AI_PROVIDER` and `AI_MODEL` in the Firebase Functions runtime environment.
- Ensure production Groq/OpenRouter keys are stored as Firebase Functions secrets, not iOS build settings.
- Verify Firestore and Storage rules are deployed.
- Run local build + tests before tagging release.

## Local Verification
```bash
xcodebuild -project TTB.xcodeproj -scheme TTB -configuration Debug build
xcodebuild -project TTB.xcodeproj -scheme TTB -destination 'platform=iOS Simulator,name=iPhone 12,OS=26.5' test
```

## App Check — do this before the first deploy of the enforced functions

The six AI callables set `enforceAppCheck: true`. Enforcement rejects any caller that presents no App
Check token, and the client reports that rejection as a network error, so the symptom does not name
the cause. Run these steps in this order. Step 3 is the point of no return for older builds.

1. **Register the app.** Firebase console › App Check › Apps › TTB › App Attest › Register. The App
   Attest capability must be on for the App ID in the Apple Developer portal.
2. **Register the debug token.** Run the debug build once on the simulator. The App Check debug
   provider logs a token on first launch (`AppCheck` category in Console). Paste it into Firebase
   console › App Check › Apps › TTB › ⋮ › Manage debug tokens. Without this, the AI features fail in
   every simulator run. Each machine and each erased simulator produces a new token.
3. **Deploy the functions.** Any installed build without the App Check SDK loses the AI features at
   this point. That is the intent — there are no users to drain — but it includes your own devices.

To undo: clear enforcement per provider in the console. Redeploying does not restore access.

## Firebase Rollout
```bash
firebase login
firebase use <project-id>
firebase functions:secrets:set GROQ_API_KEY
firebase functions:secrets:set OPENROUTER_API_KEY
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage
```

Deploy `firestore:rules` together with the functions: the rules close `aiUsageDaily/{uid}` to clients,
and that document is the daily spend counter.

## AI-Specific Validation
- Submit a query from the AI tab and verify 3 responses are returned.
- Confirm query persistence under `users/{uid}/aiQueries`.
- Confirm `users/{uid}/aiUsage/stats` counters increment. These are display only — the client writes
  them and no function reads them.
- Confirm `aiUsageDaily/{uid}` gains a `counts.aiQuery` entry under today's `dayKey`. This one is the
  spend control, and only the Admin SDK can write it.
- Confirm the App Check metrics show verified requests, not "unverified", for the six AI callables.
- Confirm provider switch (`openrouter`/`groq`) works without code change.
- Confirm the app bundle no longer contains real Groq/OpenRouter keys.

## Rollback Plan
- Revert to previous build.
- Turn App Check enforcement off in the console if attestation blocks legitimate clients. A code
  revert alone does not help: enforcement is console state, not deployed state.
- Restore prior `Info.plist` AI provider/model values.
- Re-deploy previous Firebase rules if a rule regression is detected.
