# Project-wide AI pools sit under the provider's free tier; App Check tokens are single-use

ADR-0006 gave each uid a daily AI limit and put App Check in front of the AI callables. Neither bounds
the project: a guest uid is free, and one App Check token captured from a real device can be replayed
from a script until it expires. On Groq's free tier the risk is not only a bill. Abuse traffic on our
key gets 429s first and can get the account throttled or suspended for every user.

## Decision

- **Project-wide pools per UTC day** (`functions/aiUsageLimit.js`, `PROJECT_DAILY_LIMITS`): `aiQuery`
  30 guest / 60 verified, `quickAnswers` 50 guest / 60 verified, counted in the server-owned
  `aiUsageProjectDaily/{dayKey}` document in the same transaction as the per-uid counter. Plus 20
  capped calls a minute for the whole project (`PROJECT_MINUTE_LIMIT`).
- **The numbers are derived from the provider, not from use.** Groq free tier for
  `openai/gpt-oss-120b`: 30 requests a minute, 1000 a day, 200K tokens a day. At up to ~800 tokens a
  call, 200 calls a day is ~160K tokens. The app has no users yet, so there is no use to measure.
  Recheck when the provider, the model, or `maxTokens` changes.
- **Two pools, so an attacker cannot take AI away from real users.** The pool comes from the ID token
  (`isGuestToken`): only a non-anonymous account with `email_verified === true` draws from the verified
  pool. The app sends no verification email yet, so today every account draws from the guest pool.
- **The per-uid tier did not change.** It stays anonymous vs permanent, as the client's
  `GuestCapabilityPolicy` believes, so the app's counter stays right. An unverified email account keeps
  20 AI questions a day but draws them from the guest pool.
- **Single-use App Check tokens** on the six AI callables and `suggestAnswerImages`:
  `consumeAppCheckToken: true` plus `withSingleUseAppCheck` (`functions/appCheckReplay.js`), because
  firebase-functions reports a replay in `request.app.alreadyConsumed` but does not reject it. The
  client asks for limited-use tokens (`HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)`).
  This supersedes ADR-0006's "Not claimed" line that left `suggestAnswerImages` unattested.
- **Refusals reach the user as localized text** (`TTB/Services/CallableRefusal.swift`), keyed on the
  server's `details.reason`, never on the server's English message.

## Order of operations

1. Grant the functions' runtime service account the "Firebase App Check Token Verifier" IAM role.
2. Deploy `firestore:rules`, then the seven callables in groups of at most four.
3. Ship a new app build. A build without the limited-use option (TestFlight build 9 and older) sends
   cached tokens, which the server refuses after their first use.

Deploying the callables before step 1 refuses every AI call.

## Not claimed

- One shared document per day takes every capped write. Firestore sustains about one write a second
  on one document; the minute cap keeps traffic far below that.
- Whether the App Check consume call is billed is not documented.
- Limited-use tokens with `AppCheckDebugProvider` are not verified end to end; check once on the
  simulator after the deploy.
